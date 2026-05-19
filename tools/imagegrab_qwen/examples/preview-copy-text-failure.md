---
slug: preview-copy-text-failure
kind: anti-example
files:
  - Sources/ImageGrab/CaptureOverlayWindow.swift
  - Sources/ImageGrab/TextRecognizer.swift
keywords: [preview, capturepreviewwindow, copy text, bottom bar, save & copy path, preview ocr]
---

# Anti-example: prior failed attempts to add Copy Text to CapturePreviewWindow

## What went wrong (recorded failures from earlier passes)

1. **Hallucinated `store` / `entry`.** The model produced patches that called
   `store.path(for: entry)` inside `CapturePreviewWindow`. Those symbols do not exist
   in that window — it only has `capturedImage`. The patch did not even compile.

2. **Duplicated the existing `Save & Copy Path` setup block.** The model added a second
   sequence of `saveCopyBtn.bezelStyle = ...; saveCopyBtn.controlSize = ...;
   saveCopyBtn.keyEquivalent = "\r"; ...; bar.addSubview(saveCopyBtn)` instead of
   adjusting widths/x positions to make room for a new button.

3. **Placeholder index hashes.** Diffs contained `index 9999999..5555555` rather than
   real blob hashes. `git apply --check` rejected them.

4. **Malformed unified-diff hunks.** Repeated unchanged context as `+` lines, or omitted
   leading-space context entirely.

## The correct shape

- Use `TextRecognizer.recognizeText(in: capturedImage)` — `capturedImage` is the only
  image source available inside `CapturePreviewWindow`.
- Add ONE `NSButton` (e.g., `copyTextBtn`) in `setupBottomBar`, between the existing
  size label and the right-aligned action cluster. Adjust the `saveCopyX / saveX /
  cancelX` x-position constants so the new button has room — do not stack it on top
  of `Save & Copy Path` OR `Cancel`.
- **Bottom-bar x positions chain right-to-left.** The current order from right is
  `[Save & Copy Path][Save][Cancel]` with `cancelX = saveX - gap - cancelW`. Adding
  a Copy Text button to the LEFT of Cancel means `copyTextX = cancelX - gap - copyTextW`.
  Anchoring it to `saveX - gap - copyTextW` (the same anchor Cancel uses) WILL overlap
  Cancel.
- **If the OCR action needs to read or update the button**, declare a stored property
  on the class — `private var copyTextBtn: NSButton!` — and assign to it in
  `setupBottomBar`. An `@objc` action method on `self` cannot see a `let copyTextBtn`
  that is local to `setupBottomBar`; that won't compile.
- Run OCR in `Task { @MainActor in ... }` so the pasteboard write and any button-
  title update happen on the main actor.
- Disable the button only while OCR is running; do NOT gate it on
  `annotationOverlay.hasAnnotations` or any annotation state.

## Good intent-mode shape

When asked for structured edit intent, do **not** paste the whole replacement
method. Do not include snippets; describe the edit shape with anchors and intent:

```json
{
  "summary": "Add Copy Text to the preview bottom bar.",
  "changes": [
    {
      "file": "Sources/ImageGrab/CaptureOverlayWindow.swift",
      "operation": "edit",
      "anchor": "setupBottomBar",
      "intent": "Add a Copy Text button before the existing Save/Save & Copy Path cluster and adjust x-position constants so controls do not overlap."
    },
    {
      "file": "Sources/ImageGrab/CaptureOverlayWindow.swift",
      "operation": "edit",
      "anchor": "copyTextClicked",
      "intent": "Add an async action that disables the button, calls TextRecognizer.recognizeText(in: capturedImage), copies non-empty text to NSPasteboard, shows Text Copied or No Text, then restores the title."
    }
  ],
  "verification": ["swift build", "swift test"]
}
```

## Lint signatures the harness already catches
- `store.path(for:` or stray `entry` in a diff scoped to preview Copy Text
- a second `+        saveCopyBtn.bezelStyle` line
- index hashes containing `9999999` or `5555555`
- touching `ImageGrabPopoverView.swift`, `PopoverViewModel.swift`, or
  `AppDelegate.swift` when the task is preview-window Copy Text
- intent snippets where `copyTextX = saveX - gap - copyTextW` (overlaps the existing
  Cancel button)
- intent snippets that reference `copyTextBtn` from an `@objc` action without
  declaring a stored `private var copyTextBtn` on the class
