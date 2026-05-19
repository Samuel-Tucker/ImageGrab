# ImageGrab Upgrade Options

Research collected on 2026-05-18 from open-source capture, annotation, clipboard, OCR, and gallery tools.

## Best Near-Term Fits

1. Post-capture action strip
   - Inspiration: Snapzy, Shotnix, ShareX
   - Idea: After capture, expose obvious actions such as Copy, Edit, Drag, Pin, Delete, and Copy Text.
   - Why it fits: Improves the current preview/history workflow without forcing every capture into a heavy editor.

2. Searchable capture history
   - Inspiration: Maccy, macshot, Screenpipe, PhotoPrism
   - Idea: Turn the dropdown into a fast capture shelf with search by filename/date, later OCR text, favorites, pins, and delete.
   - Why it fits: Builds on ImageGrab's existing thumbnail popover.

3. OCR / Copy Text
   - Inspiration: NormCap, Grabbit, ShareX, macshot
   - Idea: Add a visible Copy Text action on captures and possibly a dedicated OCR region hotkey.
   - Why it fits: Apple Vision can keep this local and fast.

4. Delayed capture
   - Inspiration: Flameshot, ksnip
   - Idea: Capture after a short delay for menus, tooltips, hover states, and dropdowns.
   - Why it fits: Small feature with high practical value.

5. Last-region recapture
   - Inspiration: ksnip
   - Idea: Repeat the last selected rectangle quickly.
   - Why it fits: Useful for before/after UI checks and repeated dashboard captures.

6. Pin screenshot on screen
   - Inspiration: ksnip, SnapTray, macshot
   - Idea: Turn a capture into a frameless always-on-top reference window.
   - Why it fits: Strong developer workflow for specs, comparisons, and temporary visual reference.

7. Fast gallery navigation
   - Inspiration: qView
   - Idea: Let Quick View arrow through captures, zoom, copy, drag, delete, and close.
   - Why it fits: Makes the existing capture history feel faster without adding a library manager.

## Annotation Ideas

8. Numbered callouts
   - Inspiration: Grabbit, Flameshot, macshot, Shotnix
   - Idea: Add auto-incrementing step badges.
   - Why it fits: High value for bug reports, docs, and coding-agent context.

9. First-class redaction
   - Inspiration: macshot, ksnip, ShareX
   - Idea: Add obvious Blur, Pixelate, and Solid Fill tools.
   - Why it fits: Manual redaction should be trustworthy before smart PII detection.

10. Undo and redo
    - Inspiration: Grabbit, Annotator
    - Idea: Support Cmd+Z and Cmd+Shift+Z plus visible toolbar controls.
    - Why it fits: Editing gets stressful without reversible actions.

11. Persistent tool presets
    - Inspiration: Flameshot, Grabbit
    - Idea: Remember last color, line width, text size, blur strength, and arrow style.
    - Why it fits: Adds speed without a complex settings surface.

12. Loupe / magnifier
    - Inspiration: macshot, Annotator
    - Idea: Add a magnifier annotation for tiny UI text, icons, and errors.
    - Why it fits: Useful, but lower priority than callouts, redaction, and undo/redo.

## Later / Advanced

13. Scrolling capture
    - Inspiration: ScrollSnap, Snapzy
    - Idea: A separate mode for stitched scrolling screenshots.
    - Risk: Easy to bloat the default simple capture flow.

14. Short GIF / MP4 capture
    - Inspiration: Kap, Snapzy, Capso
    - Idea: Lightweight region recording for quick bug reports.
    - Risk: Should wait until still-image capture is excellent.

15. Optional share / upload
    - Inspiration: ShareX, Flameshot, macshot
    - Idea: Explicit Share action with destinations.
    - Risk: Keep local-first; avoid automatic upload behavior.

## Reference Projects

- Snapzy: https://github.com/duongductrong/Snapzy
- Shotnix: https://github.com/OMARVII/Shotnix
- Grabbit: https://github.com/recursivecodes/grabbit
- macshot: https://github.com/sw33tLie/macshot
- ksnip: https://github.com/ksnip/ksnip
- Flameshot: https://github.com/flameshot-org/flameshot
- ShareX: https://github.com/ShareX/ShareX
- NormCap: https://github.com/dynobo/normcap
- Maccy: https://github.com/p0deje/Maccy
- Kap: https://github.com/wulkano/Kap
- qView: https://github.com/jurplel/qView
- ScrollSnap: https://github.com/Brkgng/ScrollSnap
- Screenpipe: https://github.com/screenpipe/screenpipe
- TagStudio: https://github.com/TagStudioDev/TagStudio
- PhotoPrism: https://github.com/photoprism/photoprism
