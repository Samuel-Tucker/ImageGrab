#!/usr/bin/env python3
"""Deterministic eval runner for the ImageGrab qwen-local harness.

Exercises file selection, example routing, and the patch lint on each task in
`imagegrab_evals.json` WITHOUT calling the Qwen server. Useful for catching
regressions in the harness (routing, lint patterns, example index) even when
port 18081 is not listening.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools" / "imagegrab_qwen"))

import imagegrab_qwen as harness  # noqa: E402  - sys.path injection above


SPEC_PATH = Path(__file__).with_name("imagegrab_evals.json")


def load_spec() -> dict:
    return json.loads(SPEC_PATH.read_text(encoding="utf-8"))


def synthetic_bad_patch_for(task_id: str) -> str:
    """Return a deliberately-broken patch the lint must catch, per task.

    Returns "" for tasks where no lint rule is exercised — those are reported as
    skipped rather than failures.
    """
    if task_id == "preview-copy-text":
        return (
            "diff --git a/Sources/ImageGrab/CaptureOverlayWindow.swift "
            "b/Sources/ImageGrab/CaptureOverlayWindow.swift\n"
            "index 9999999..5555555 100644\n"
            "--- a/Sources/ImageGrab/CaptureOverlayWindow.swift\n"
            "+++ b/Sources/ImageGrab/CaptureOverlayWindow.swift\n"
            "@@ -1,1 +1,3 @@\n"
            " import AppKit\n"
            "+let path = store.path(for: entry)\n"
            "+        saveCopyBtn.bezelStyle = .rounded\n"
            "diff --git a/Sources/ImageGrab/ImageGrabPopoverView.swift "
            "b/Sources/ImageGrab/ImageGrabPopoverView.swift\n"
            "index 1111111..2222222 100644\n"
            "--- a/Sources/ImageGrab/ImageGrabPopoverView.swift\n"
            "+++ b/Sources/ImageGrab/ImageGrabPopoverView.swift\n"
            "@@ -1,1 +1,2 @@\n"
            " import SwiftUI\n"
            "+// touched forbidden file\n"
        )
    return ""


def check_file_selection(task: dict) -> list[str]:
    selected = harness.select_files(task["task"], [])
    missing = [f for f in task.get("expected_files", []) if f not in selected]
    return missing


def check_example_routing(task: dict) -> list[str]:
    if not hasattr(harness, "select_examples"):
        return ["harness has no select_examples() — examples not wired in"]
    expected = task.get("expected_examples", [])
    if not expected:
        return []
    chosen = [ex["slug"] for ex in harness.select_examples(task["task"])]
    return [slug for slug in expected if slug not in chosen]


def check_patch_lint(task: dict) -> list[str]:
    if task.get("kind") != "patch":
        return []
    expectations = task.get("patch_lint_must_catch", [])
    if not expectations:
        return []
    bad_diff = synthetic_bad_patch_for(task["id"])
    if not bad_diff:
        return [f"no synthetic bad patch defined for {task['id']}"]
    ok, detail = harness.lint_patch(bad_diff, task["task"])
    if ok:
        return ["lint failed to flag a deliberately-broken patch: " + detail]
    missing = [needle for needle in expectations if needle not in detail]
    return ["lint did not mention: " + m for m in missing]


def main() -> int:
    spec = load_spec()
    failures: list[str] = []
    skipped: list[str] = []

    for task in spec["tasks"]:
        tid = task["id"]
        sel_missing = check_file_selection(task)
        if sel_missing:
            failures.append(f"[{tid}] file selection missing: {sel_missing}")
        ex_missing = check_example_routing(task)
        if ex_missing:
            if ex_missing == ["harness has no select_examples() — examples not wired in"]:
                skipped.append(f"[{tid}] examples not wired in (harness pre-update)")
            else:
                failures.append(f"[{tid}] expected examples not routed: {ex_missing}")
        lint_problems = check_patch_lint(task)
        for problem in lint_problems:
            failures.append(f"[{tid}] {problem}")

    print(f"evaluated {len(spec['tasks'])} task(s)")
    for note in skipped:
        print(f"  SKIP {note}")
    if failures:
        print("FAILURES:")
        for line in failures:
            print(f"  - {line}")
        return 1
    print("OK — all eval checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
