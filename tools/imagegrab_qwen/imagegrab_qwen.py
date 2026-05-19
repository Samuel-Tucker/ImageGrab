#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


DEFAULT_BASE_URL = "http://127.0.0.1:18081/v1"
DEFAULT_MODEL = "/Users/sam/llms/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit"
ROOT = Path(__file__).resolve().parents[2]
EXAMPLES_DIR = Path(__file__).resolve().parent / "examples"
EXAMPLES_INDEX = EXAMPLES_DIR / "index.json"

TEXT_SUFFIXES = {".swift", ".md", ".plist", ".json", ".yml", ".yaml", ".txt"}
EXCLUDE_DIRS = {".git", ".build", ".swiftpm", "captures", "dist"}

ROLE_FILES = {
    "preview": [
        "Sources/ImageGrab/CaptureOverlayWindow.swift",
        "Sources/ImageGrab/TextRecognizer.swift",
        "Sources/ImageGrab/AnnotationOverlayView.swift",
    ],
    "popover": [
        "Sources/ImageGrab/ImageGrabPopoverView.swift",
        "Sources/ImageGrab/PopoverViewModel.swift",
        "Sources/ImageGrab/CaptureStore.swift",
        "Sources/ImageGrab/TextRecognizer.swift",
    ],
    "ocr": [
        "Sources/ImageGrab/TextRecognizer.swift",
        "Sources/ImageGrab/PopoverViewModel.swift",
        "Sources/ImageGrab/ImageGrabPopoverView.swift",
        "Sources/ImageGrab/CaptureOverlayWindow.swift",
    ],
    "capture": [
        "Sources/ImageGrab/AppDelegate.swift",
        "Sources/ImageGrab/CaptureStore.swift",
        "Sources/ImageGrab/GlobalHotKeyManager.swift",
    ],
    "annotation": [
        "Sources/ImageGrab/AnnotationOverlayView.swift",
        "Tests/ImageGrabKitTests/AnnotationOverlayViewTests.swift",
        "Sources/ImageGrab/CaptureOverlayWindow.swift",
    ],
    "packaging": [
        "Scripts/build_app.sh",
        "Scripts/build_release_assets.sh",
        "Support/Info.plist",
        "docs/releasing.md",
        "README.md",
    ],
}

SYSTEM_PROMPT = """You are qwen-local, Sam's local Swift specialist for ImageGrab.
You are helping in /Users/sam/repos/ImageGrab, a small native macOS menu-bar screenshot app.

Hard project rules:
- Keep changes small and reviewable.
- Do not rewrite unrelated code or move responsibilities between app surfaces.
- AppDelegate owns global hotkeys and capture lifecycle only.
- CapturePreviewWindow in CaptureOverlayWindow.swift owns post-capture preview, annotation, filename, save/cancel UI.
- ImageGrabPopoverView owns capture-history thumbnail UI and visible thumbnail actions.
- PopoverViewModel mediates capture-history actions against CaptureStore.
- CaptureStore owns capture files, metadata, thumbnails, drag export paths, and persistence.
- AnnotationOverlayView owns annotation editing, hit testing, undo/redo, and compositing.
- TextRecognizer is the local Apple Vision OCR helper. Do not create a duplicate OCR helper.
- OCR must not depend on whether annotations exist.
- Do not map new shortcuts to existing undo/redo actions.
- Preserve local-first behavior. Do not add uploads, cloud calls, analytics, or network dependencies.
- Prefer existing AppKit/SwiftUI style and current file boundaries.
- For patches, return one unified diff only. No markdown fences, no prose before the diff.
- A useful patch must apply with git apply --check and should preserve swift build and swift test.
- Never invent variables that are not in the selected files. If the preview window has no `store` or `entry`, do not use `store.path(for:)` or `entry`.
- Prefer a text-label button over adding extra icon-only controls when editing the preview bottom bar.
- Patch hunks must be mechanically valid unified diffs. Do not use placeholder index hashes such as `9999999`.
- Do not duplicate unchanged blocks inside a hunk. If a block already exists, include it as context with leading spaces, not added lines.
"""


class HarnessError(RuntimeError):
    pass


@dataclass(frozen=True)
class ChatOptions:
    max_tokens: int
    temperature: float = 0.0
    stream: bool = False
    timeout: int = 900


def run(args: list[str], *, cwd: Path = ROOT, timeout: int = 300) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=timeout, check=False)


def repo_status() -> str:
    proc = run(["git", "status", "--short"])
    return proc.stdout.strip() or "(clean working tree)"


def repo_diff(limit_lines: int = 900) -> str:
    proc = run(["git", "diff"])
    out = proc.stdout.strip()
    return clip_lines(out, limit_lines) if out else "(no diff)"


def read_file(relpath: str, *, max_lines: int = 260) -> str:
    path = safe_path(relpath)
    if not path.is_file():
        return f"### {relpath}\n(file missing)\n"
    if path.suffix and path.suffix not in TEXT_SUFFIXES:
        return f"### {relpath}\n(non-text file skipped)\n"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    clipped = lines[:max_lines]
    body = "\n".join(f"{i + 1:>5} {line}" for i, line in enumerate(clipped))
    if len(lines) > max_lines:
        body += f"\n... [{len(lines) - max_lines} more lines clipped]"
    return f"### {relpath}\n{body}\n"


def safe_path(relpath: str) -> Path:
    root = ROOT.resolve()
    path = (ROOT / relpath).resolve() if not Path(relpath).is_absolute() else Path(relpath).resolve()
    if path != root and root not in path.parents:
        raise HarnessError(f"path escapes repo root: {relpath}")
    return path


def clip_lines(text: str, limit: int) -> str:
    lines = text.splitlines()
    if len(lines) <= limit:
        return text
    return "\n".join(lines[:limit]) + f"\n... [{len(lines) - limit} more lines clipped]"


def select_files(task: str, explicit: list[str]) -> list[str]:
    selected: list[str] = []
    for rel in explicit:
        add_unique(selected, normalize_relpath(rel))

    lower = task.lower()
    role_hits = {
        "preview": ("preview", "post-capture", "capturepreviewwindow", "bottom bar", "save & copy"),
        "popover": ("popover", "thumbnail", "history", "hover", "copy path", "grid"),
        "ocr": ("ocr", "copy text", "textrecognizer", "vision", "recognized text"),
        "capture": ("hotkey", "screencapture", "capture lifecycle", "clipboard polling", "cancel"),
        "annotation": ("annotation", "pen", "box", "arrow", "text tool", "undo", "redo", "redaction"),
        "packaging": ("package", "release", "dmg", "zip", "codesign", "notar"),
    }
    for role, needles in role_hits.items():
        if any(needle in lower for needle in needles):
            for rel in ROLE_FILES[role]:
                add_unique(selected, rel)

    if not selected:
        for rel in [
            "README.md",
            "Sources/ImageGrab/ImageGrabPopoverView.swift",
            "Sources/ImageGrab/CaptureOverlayWindow.swift",
            "Sources/ImageGrab/PopoverViewModel.swift",
        ]:
            add_unique(selected, rel)

    return selected[:8]


def normalize_relpath(path: str) -> str:
    p = Path(path)
    if p.is_absolute():
        return str(p.resolve().relative_to(ROOT.resolve()))
    return path


def add_unique(items: list[str], value: str) -> None:
    if value not in items:
        items.append(value)


def load_examples_index() -> list[dict]:
    if not EXAMPLES_INDEX.is_file():
        return []
    try:
        return json.loads(EXAMPLES_INDEX.read_text(encoding="utf-8")).get("examples", [])
    except (json.JSONDecodeError, OSError):
        return []


def select_examples(task: str, *, limit: int = 2) -> list[dict]:
    """Return example entries whose keywords appear in `task`. Deterministic
    ordering: matches sorted by descending hit count, ties broken by the order
    in `index.json`. Empty list if nothing matches.
    """
    lower = task.lower()
    scored: list[tuple[int, int, dict]] = []
    for order, entry in enumerate(load_examples_index()):
        hits = sum(1 for kw in entry.get("keywords", []) if kw.lower() in lower)
        if hits:
            scored.append((-hits, order, entry))
    scored.sort()
    return [entry for _, _, entry in scored[:limit]]


def render_examples(entries: list[dict]) -> str:
    if not entries:
        return ""
    out: list[str] = []
    for entry in entries:
        path = EXAMPLES_DIR / entry.get("file", "")
        if not path.is_file():
            continue
        body = path.read_text(encoding="utf-8", errors="replace").rstrip()
        kind = entry.get("kind", "example")
        slug = entry.get("slug", path.stem)
        out.append(f"### example: {slug} ({kind})\n{body}\n")
    return "\n".join(out)


def automatic_context(task: str, files: list[str], *, include_diff: bool) -> str:
    parts = [
        "## Repo status",
        repo_status(),
        "",
        "## ImageGrab file-boundary map",
        "- AppDelegate.swift: hotkeys and capture lifecycle.",
        "- CaptureOverlayWindow.swift: post-capture preview, annotation toolbar, bottom save/cancel bar.",
        "- ImageGrabPopoverView.swift: menu-bar popover, thumbnail grid, copy/preview/edit/delete UI.",
        "- PopoverViewModel.swift: capture-history actions and clipboard writes.",
        "- CaptureStore.swift: files, metadata, thumbnails, drag exports.",
        "- AnnotationOverlayView.swift: annotation state, editing, hit testing, compositing.",
        "- TextRecognizer.swift: local Apple Vision OCR. Reuse it; do not duplicate it.",
        "",
        "## Selected files",
    ]
    for rel in files:
        parts.append(read_file(rel))
    if "CaptureOverlayWindow.swift" in "\n".join(files):
        parts.extend(["", "## CapturePreviewWindow focused landmarks", capture_preview_landmarks()])
    task_notes = task_specific_notes(task)
    if task_notes:
        parts.extend(["", "## Task-specific constraints", task_notes])
    examples = select_examples(task)
    if examples:
        parts.extend(["", "## Relevant examples (golden + anti-examples)", render_examples(examples)])
    if include_diff:
        parts.extend(["", "## Current git diff", repo_diff()])
    return "\n".join(parts)


def capture_preview_landmarks() -> str:
    path = safe_path("Sources/ImageGrab/CaptureOverlayWindow.swift")
    if not path.is_file():
        return "(CaptureOverlayWindow.swift missing)"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    ranges = [(1, 40), (214, 270), (300, 370)]
    chunks: list[str] = []
    for start, end in ranges:
        selected = lines[start - 1 : min(end, len(lines))]
        body = "\n".join(f"{idx:>5} {line}" for idx, line in enumerate(selected, start=start))
        chunks.append(body)
    return "\n\n".join(chunks)


def task_specific_notes(task: str) -> str:
    lower = task.lower()
    notes: list[str] = []
    if "copy text" in lower and ("preview" in lower or "capturepreviewwindow" in lower or "bottom bar" in lower):
        notes.extend([
            "- This is preview-window OCR. Do not touch ImageGrabPopoverView or PopoverViewModel unless explicitly asked.",
            "- CapturePreviewWindow has `capturedImage`; use `TextRecognizer.recognizeText(in: capturedImage)`.",
            "- CapturePreviewWindow does not have `store` or `entry`; using them is an immediate failure.",
            "- The button belongs in `setupBottomBar`, near `Cancel`, `Save`, and `Save & Copy Path`.",
            "- Existing `saveCopyBtn` setup already exists. Do not add a second `saveCopyBtn.bezelStyle/controlSize/keyEquivalent/frame/addSubview` block.",
            "- If space is needed, adjust bottom-bar width constants and x positions coherently before creating the controls.",
            "- Add stored references only for controls that must be updated later, such as `copyTextBtn`.",
            "- AppKit UI updates after async OCR must run on the main actor.",
            "- OCR should be available before annotations exist; disable only while OCR is running.",
            "- A valid button action can use `Task { @MainActor in ... }` or return to `MainActor.run` for pasteboard/UI updates.",
        ])
    return "\n".join(notes)


INTENT_INSTRUCTION = (
    "Return ONE JSON object describing the smallest correct edit, and NOTHING else "
    "(no prose, no markdown fences). Schema:\n"
    "{\n"
    '  "summary": "<one short sentence>",\n'
    '  "rationale": "<why this change is in scope and within file boundaries>",\n'
    '  "changes": [\n'
    "    {\n"
    '      "file": "<repo-relative path that exists>",\n'
    '      "operation": "edit" | "create",\n'
    '      "anchor": "<function or symbol name where the edit lands>",\n'
    '      "intent": "<what to add/remove/rename, in one or two sentences>"\n'
    "    }\n"
    "  ],\n"
    '  "verification": ["swift build", "swift test"]\n'
    "}\n"
    "Anchor rules: for an edit that MODIFIES an existing function, use the existing "
    "function's name. For an edit that ADDS a NEW function, use the NAME OF THE NEW "
    "FUNCTION (e.g. `copyTextClicked`), not the name of a sibling method nearby — "
    "anchors identify the symbol the change creates or changes, not the location it "
    "appears next to.\n"
    "General rules: only reference symbols that exist in the selected files; never "
    "propose duplicate OCR helpers; never widen scope beyond the file-boundary map; "
    "never include snippets, full methods, or full implementations; use intent/anchor "
    "fields only to describe the edit shape; never claim verification you did not "
    "perform — list the commands a human should run."
)


def task_prompt(kind: str, task: str, context: str) -> str:
    if kind == "plan":
        instruction = (
            "Produce a concrete implementation plan. Do not include a diff. "
            "Call out file boundaries, UI state, verification commands, and likely mistakes."
        )
    elif kind == "patch":
        instruction = (
            "Return the smallest correct unified diff only. No markdown fences. "
            "Do not repeat existing code that is already in the current context. "
            "Before returning, mentally verify every referenced variable exists in the selected files."
        )
    elif kind == "review":
        instruction = (
            "Review the current diff. Findings first, with file/line references when possible. "
            "Prioritize bugs, regressions, missing tests, and Swift/AppKit lifecycle risks. "
            "Only report findings grounded in the provided diff or selected files. "
            "Do not include speculative 'might/could' issues unless you can name the exact code path. "
            "If the main risk is missing verification, say that directly and keep it short."
        )
    elif kind == "intent":
        instruction = INTENT_INSTRUCTION
    else:
        instruction = "Answer from the repo context. Be concise and cite concrete files."

    return f"""Task type: {kind}

User request:
{task}

Instruction:
{instruction}

Context:
{context}
"""


def model_chat(messages: list[dict[str, str]], args: argparse.Namespace) -> str:
    payload = {
        "model": args.model,
        "messages": messages,
        "max_tokens": args.max_tokens,
        "temperature": 0.0,
        "stream": False,
    }
    req = urllib.request.Request(
        f"{args.base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.URLError as exc:
        raise HarnessError(f"Could not reach Qwen server at {args.base_url}: {exc}") from exc
    try:
        return data["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError, TypeError) as exc:
        raise HarnessError(f"Unexpected Qwen response: {data}") from exc


def extract_diff(text: str) -> str | None:
    fenced = re.search(r"```(?:diff|patch)?\n(.*?)```", text, re.DOTALL)
    if fenced and "diff --git " in fenced.group(1):
        return fenced.group(1).strip() + "\n"
    idx = text.find("diff --git ")
    if idx == -1:
        return None
    return text[idx:].strip() + "\n"


def extract_intent_json(text: str) -> dict | None:
    """Find the first top-level JSON object in `text` and return it parsed.

    Tolerates a leading ```json fence and trailing prose. Returns None on
    parse failure.
    """
    fenced = re.search(r"```(?:json)?\s*\n(\{.*?\})\s*```", text, re.DOTALL)
    candidate = fenced.group(1) if fenced else None
    if candidate is None:
        start = text.find("{")
        if start == -1:
            return None
        depth = 0
        end = -1
        for i, ch in enumerate(text[start:], start=start):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        if end == -1:
            return None
        candidate = text[start:end]
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        return None


def validate_intent(intent: dict, task: str) -> tuple[bool, list[str], list[str]]:
    """Return (ok, problems, summary_lines). Never applies edits."""
    problems: list[str] = []
    summary: list[str] = []

    if not isinstance(intent, dict):
        return False, ["intent is not a JSON object"], []

    for required in ("summary", "changes"):
        if required not in intent:
            problems.append(f"missing required key: {required}")
    if problems:
        return False, problems, summary

    summary.append(f"summary: {intent.get('summary', '').strip()}")
    if intent.get("rationale"):
        summary.append(f"rationale: {intent['rationale'].strip()}")

    changes = intent.get("changes")
    if not isinstance(changes, list) or not changes:
        problems.append("changes must be a non-empty list")
        return False, problems, summary

    lower_task = task.lower()
    forbidden_for_preview_ocr = {
        "Sources/ImageGrab/ImageGrabPopoverView.swift",
        "Sources/ImageGrab/PopoverViewModel.swift",
        "Sources/ImageGrab/AppDelegate.swift",
    }
    preview_ocr_task = "copy text" in lower_task and (
        "preview" in lower_task
        or "capturepreviewwindow" in lower_task
        or "bottom bar" in lower_task
    )

    for idx, change in enumerate(changes):
        if not isinstance(change, dict):
            problems.append(f"changes[{idx}] is not an object")
            continue
        rel = change.get("file", "")
        op = change.get("operation", "edit")
        intent_text = change.get("intent", "").strip()
        anchor = change.get("anchor", "").strip()
        snippet = change.get("snippet", "")
        if "snippet" in change:
            problems.append(f"changes[{idx}]: remove snippet; intent mode should describe edits without code bodies")
        if not rel:
            problems.append(f"changes[{idx}].file is empty")
            continue
        try:
            path = safe_path(rel)
        except HarnessError as exc:
            problems.append(f"changes[{idx}]: {exc}")
            continue
        if op not in {"edit", "create"}:
            problems.append(f"changes[{idx}].operation must be 'edit' or 'create' (got {op!r})")
        if op == "edit" and not path.is_file():
            problems.append(f"changes[{idx}]: edit target does not exist: {rel}")
        if op == "create" and path.exists():
            problems.append(f"changes[{idx}]: create target already exists: {rel}")
        if preview_ocr_task and rel in forbidden_for_preview_ocr:
            problems.append(f"changes[{idx}]: touches forbidden file for preview Copy Text: {rel}")
        if "OCRTextRecognizer" in snippet or "OCRService" in snippet:
            problems.append(f"changes[{idx}]: snippet introduces a duplicate OCR helper")
        summary.append(f"  - [{op}] {rel} :: {anchor or '(no anchor)'} — {intent_text or '(no intent)'}")

    verification = intent.get("verification")
    if isinstance(verification, list) and verification:
        summary.append("verification commands suggested: " + ", ".join(str(v) for v in verification))
    else:
        summary.append("(no verification commands suggested)")

    return not problems, problems, summary


def check_patch(diff: str) -> tuple[bool, str]:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".patch", delete=False) as handle:
        handle.write(diff)
        patch_path = handle.name
    try:
        proc = run(["git", "apply", "--check", patch_path])
        detail = "\n".join(part for part in [proc.stdout.strip(), proc.stderr.strip()] if part)
        return proc.returncode == 0, detail or "patch applies cleanly"
    finally:
        Path(patch_path).unlink(missing_ok=True)


def run_task(kind: str, args: argparse.Namespace) -> int:
    files = select_files(args.task, args.file)
    context = automatic_context(args.task, files, include_diff=kind == "review" or args.include_diff)
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": task_prompt(kind, args.task, context)},
    ]
    answer = model_chat(messages, args)
    print(answer)
    if kind == "patch":
        diff = extract_diff(answer)
        if not diff:
            print("\n[patch check] no unified diff found", file=sys.stderr)
            return 2
        ok, detail = check_patch(diff)
        lint_ok, lint_detail = lint_patch(diff, args.task)
        if ok and lint_ok:
            print(f"\n[patch check] {detail}", file=sys.stderr)
            return 0
        if not ok:
            print(f"\n[patch check] does not apply: {detail}", file=sys.stderr)
        if not lint_ok:
            print(f"\n[patch lint] {lint_detail}", file=sys.stderr)
        return 3
    if kind == "intent":
        intent = extract_intent_json(answer)
        if intent is None:
            print("\n[intent check] no JSON object found in response", file=sys.stderr)
            return 2
        ok, problems, summary = validate_intent(intent, args.task)
        print("\n[intent summary]", file=sys.stderr)
        for line in summary:
            print(line, file=sys.stderr)
        if ok:
            print("\n[intent check] structure OK — NOT auto-applied; review manually before editing.", file=sys.stderr)
            return 0
        print("\n[intent check] problems:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 3
    return 0


def lint_patch(diff: str, task: str) -> tuple[bool, str]:
    lower = task.lower()
    problems: list[str] = []
    if "copy text" in lower and ("preview" in lower or "capturepreviewwindow" in lower or "bottom bar" in lower):
        if "store.path(for:" in diff or "entry" in diff:
            problems.append("preview-window Copy Text patch references store/entry; CapturePreviewWindow has capturedImage instead")
        if re.search(r"^\+        saveCopyBtn\.bezelStyle", diff, re.MULTILINE):
            problems.append("patch appears to duplicate the existing Save & Copy Path button setup")
        if "9999999" in diff or "5555555" in diff:
            problems.append("patch uses placeholder git index hashes")
        if "+        let copyTextX = width - pad - copyTextW" in diff and "saveCopyX = width - pad - saveCopyW" in diff:
            problems.append("copyTextX overlaps the existing right-aligned Save & Copy Path button")
        touched = set(re.findall(r"^\+\+\+ b/(.+)$", diff, re.MULTILINE))
        forbidden = {
            "Sources/ImageGrab/ImageGrabPopoverView.swift",
            "Sources/ImageGrab/PopoverViewModel.swift",
            "Sources/ImageGrab/AppDelegate.swift",
        }
        bad = sorted(touched & forbidden)
        if bad:
            problems.append("patch touches forbidden files for preview OCR: " + ", ".join(bad))
    return (not problems, "; ".join(problems) or "patch lint passed")


def cmd_status(args: argparse.Namespace) -> int:
    req = urllib.request.Request(f"{args.base_url.rstrip('/')}/models", method="GET")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as exc:
        print(f"Qwen unavailable at {args.base_url}: {exc}", file=sys.stderr)
        return 1
    print(f"Endpoint: {args.base_url.rstrip('/')}")
    print(f"Requested model: {args.model}")
    print(body)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ImageGrab-specific qwen-local harness.")
    parser.add_argument("--base-url", default=os.environ.get("QWEN_BASE_URL", DEFAULT_BASE_URL))
    parser.add_argument("--model", default=os.environ.get("QWEN_MODEL", DEFAULT_MODEL))
    parser.add_argument("--max-tokens", type=int, default=3500)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--include-diff", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    for name in ("ask", "plan", "patch", "review", "intent"):
        cmd = sub.add_parser(name)
        default_task = "Review the current diff." if name == "review" else None
        cmd.add_argument("task", nargs="?" if default_task else None, default=default_task)
        cmd.add_argument("-f", "--file", action="append", default=[], help="Pin a repo-relative file.")

    sub.add_parser("status")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "status":
            return cmd_status(args)
        return run_task(args.command, args)
    except HarnessError as exc:
        print(f"imagegrab-qwen: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
