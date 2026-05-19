# ImageGrab Qwen Harness

`bin/imagegrab-qwen` is a repo-local wrapper for the local Qwen 30B coder model.
It is deliberately conservative: it gathers ImageGrab-specific context, asks the
model for a plan/review/patch/intent, and checks any returned patch with
`git apply --check`. It never applies patches or edits automatically.

## Requirements

The local Qwen OpenAI-compatible server should be running on port `18081`.
The Brain harness can start and verify it:

```sh
cd /Users/sam/repos/Brain
./bin/brain-qwen qwen start
./bin/brain-qwen qwen ping
```

Expected model:

```text
/Users/sam/llms/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit
```

If the server is down, `intent`/`patch`/`plan`/`review` will fail with a clear
"Could not reach Qwen server" message. The deterministic eval runner
(`tools/imagegrab_qwen/evals/run_evals.py`) still works offline.

## Commands

```sh
bin/imagegrab-qwen status
bin/imagegrab-qwen plan   "Add Copy Text to the preview window"
bin/imagegrab-qwen patch  "Add Copy Text to the preview window"
bin/imagegrab-qwen intent "Add Copy Text to the preview window"
bin/imagegrab-qwen review
bin/imagegrab-qwen ask    "Where should delayed capture live?"
```

Pin files when the automatic router is not enough:

```sh
bin/imagegrab-qwen plan \
  -f Sources/ImageGrab/CaptureOverlayWindow.swift \
  -f Sources/ImageGrab/TextRecognizer.swift \
  "Add Copy Text to the preview bottom bar"
```

## Built-in Routing

The harness selects likely files from task wording:

| Task area | Primary files |
| --- | --- |
| Preview window | `CaptureOverlayWindow.swift`, `TextRecognizer.swift`, `AnnotationOverlayView.swift` |
| Popover/history | `ImageGrabPopoverView.swift`, `PopoverViewModel.swift`, `CaptureStore.swift` |
| OCR / Copy Text | `TextRecognizer.swift`, `PopoverViewModel.swift`, `ImageGrabPopoverView.swift`, `CaptureOverlayWindow.swift` |
| Capture lifecycle | `AppDelegate.swift`, `CaptureStore.swift`, `GlobalHotKeyManager.swift` |
| Annotation tools | `AnnotationOverlayView.swift`, annotation tests, `CaptureOverlayWindow.swift` |
| Packaging | build scripts, `Info.plist`, release docs, README |

## Examples

`tools/imagegrab_qwen/examples/` holds compact golden and anti-example notes that
the harness can route into the prompt based on task keywords. Each example is a
short Markdown file with YAML-style frontmatter (`slug`, `kind`, `files`,
`keywords`) and a small "Don't" section.

Current examples:

| Slug | Kind | What it teaches |
| --- | --- | --- |
| `ocr-popover` | golden | The shape of OCR / Copy Text wired through `TextRecognizer` → `PopoverViewModel.copyText` → popover UI. |
| `hover-helper-overlay` | golden | Single-enum hovered-action state + in-thumbnail capsule caption. |
| `preview-copy-text-failure` | anti-example | Prior failures when adding Copy Text to `CapturePreviewWindow` (hallucinated `store/entry`, duplicated `Save & Copy Path`, placeholder index hashes). |

Routing is deterministic: any keyword from `index.json` that appears in the task
text qualifies an example. The top two scoring examples are rendered into the
prompt under `## Relevant examples`.

## Evals

`tools/imagegrab_qwen/evals/imagegrab_evals.json` declares a small fixed set of
ImageGrab tasks with `expected_files`, `forbidden_files`, `forbidden_symbols`,
and `expected_examples`. Tasks cover:

1. `preview-copy-text` — preview-window Copy Text patch.
2. `ocr-test` — TextRecognizer unit test patch.
3. `delayed-capture-plan` — planning a countdown-capture hotkey.
4. `popover-ui-polish` — patch tightening the hover caption state surface.
5. `capture-lifecycle-review` — review the current diff for lifecycle regressions.

`run_evals.py` exercises the harness's deterministic side (file routing, example
selection, patch lint against a synthetic broken diff) without calling the Qwen
server, so it stays green even when port 18081 is not listening:

```sh
python3 tools/imagegrab_qwen/evals/run_evals.py
```

## Patch Mode

`patch` extracts any unified diff from the response and runs:

```sh
git apply --check <patch>
```

It also runs `lint_patch`, which flags the recorded preview-OCR failure modes
(hallucinated `store/entry`, duplicated `saveCopyBtn` setup, placeholder index
hashes, touching forbidden files). If either check fails, the harness reports
the failure and leaves the worktree unchanged.

## Intent Mode (structured, no auto-apply)

`intent` asks Qwen for a JSON edit-intent instead of a unified diff. It is
useful when Qwen struggles to produce a mechanically valid diff but can still
describe the right change cleanly.

Response schema:

```json
{
  "summary": "<one short sentence>",
  "rationale": "<why this change is in scope>",
  "changes": [
    {
      "file": "<repo-relative path that exists>",
      "operation": "edit" | "create",
      "anchor": "<function or symbol name>",
      "intent": "<what to add/remove/rename>"
    }
  ],
  "verification": ["swift build", "swift test"]
}
```

The harness validates the schema, checks that every `edit` target exists and
every `create` target does not, rejects `snippet` keys so intent stays at the
planning/edit-shape level, refuses duplicate OCR-helper references, and enforces
the preview-OCR forbidden-file list.
**It never applies the intent.** Output is a printed summary the human reviews
before editing manually.

## Guardrails

The system prompt tells Qwen:

- Reuse `TextRecognizer`; do not create duplicate OCR helpers.
- Do not make OCR depend on annotation state.
- Do not map new shortcuts to undo/redo actions.
- Keep `AppDelegate` focused on hotkeys and capture lifecycle.
- Keep preview-window work in `CaptureOverlayWindow.swift`.
- Keep thumbnail/history UI work in `ImageGrabPopoverView.swift`.
- Return unified diffs only for patch mode; JSON without snippets for intent mode.

## Current Assessment

The first smoke test on the preview-window Copy Text task showed improvement in
context selection but not enough patch reliability. Qwen produced a non-applying
diff, and the harness rejected it. Treat `patch` as supervised; treat `intent`
as the safer alternative when iterating on a change Qwen cannot diff cleanly.

Useful behavior has improved first in `plan` and `intent` modes: Qwen reliably
identifies that preview-window OCR should use `capturedImage` and not
`store`/`entry`, and the new examples make that pattern explicit. The first
successful intent pass for preview Copy Text produced the right file and scope,
but its action anchor was still slightly imprecise (`saveAndCopyPathClicked`
instead of a new `copyTextClicked` action). Treat intent output as a useful
brief, not an implementation.

`patch` still needs human review and benefits significantly from `-f` pinning
plus the `patch_lint` failure signatures.

### Known limitations

- `intent` output is not auto-applied; humans must hand-edit.
- Example routing is keyword-based, not semantic. Misnamed tasks may miss the
  relevant example.
- The eval runner skips model inference entirely; it cannot catch model-side
  regressions (only harness-side ones).
- Patch lint signatures are scoped to known preview-OCR failure modes; new
  failure modes need new lint rules in `imagegrab_qwen.py::lint_patch`.
