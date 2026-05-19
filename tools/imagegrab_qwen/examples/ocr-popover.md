---
slug: ocr-popover
kind: golden
files:
  - Sources/ImageGrab/TextRecognizer.swift
  - Sources/ImageGrab/PopoverViewModel.swift
  - Sources/ImageGrab/ImageGrabPopoverView.swift
keywords: [ocr, copy text, vision, recognized text, textrecognizer, popover, thumbnail copy text]
---

# Example: OCR / Copy Text in popover thumbnail

## Intent
Add a visible "Copy Text" action to capture-history thumbnails. Run Apple Vision OCR
locally, write the recognized text to `NSPasteboard.general`, and surface clear
"Reading / Text Copied / No Text" UI states.

## Golden structure

1. **Sources/ImageGrab/TextRecognizer.swift** owns ALL OCR. It is `public enum TextRecognizer`
   with `recognizeText(at: URL)` / `(in: NSImage)` / `(in: CGImage)`. It throws
   `TextRecognizerError.noTextFound` when Vision succeeds but the image has no readable
   text — callers branch on this to drive UI feedback. Do NOT create a duplicate helper
   named `OCRTextRecognizer` or `OCRService`.

   ```swift
   public static func recognizeText(at url: URL, languages: [String] = ["en-US"]) async throws -> String
   ```

2. **Sources/ImageGrab/PopoverViewModel.swift** exposes `copyText(for: CaptureEntry) async -> Bool`.
   It resolves the capture URL via `store.path(for:)`, awaits `TextRecognizer.recognizeText(at:)`,
   writes the result to `NSPasteboard.general`, beeps on failure, returns the bool the
   SwiftUI view uses to flip its state. The view model is `@MainActor`; do not add
   `DispatchQueue.main.async` wrappers inside it.

3. **Sources/ImageGrab/ImageGrabPopoverView.swift** wires the UI: a `text.viewfinder` icon
   in the per-thumbnail hover strip AND a full-width "Copy Text" button below "Copy Path".
   The view holds three transient `@State` flags — `recognizingTextID`, `copiedTextID`,
   `noTextID` — and starts a `Task { ... }` that flips `recognizingTextID` first, then
   either `copiedTextID` (success) or `noTextID` (failure) with a ~1s clear timer.

## Don't
- Don't move OCR logic into the popover view; the view model is the mediator.
- Don't duplicate OCR (no `OCRService`, no Vision request in `CaptureStore`).
- Don't gate OCR on whether annotations exist.
