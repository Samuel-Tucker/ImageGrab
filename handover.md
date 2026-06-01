# ImageGrab Handover

Updated: 2026-05-19 20:40 Europe/London

## Current State

Repo: `/Users/sam/repos/ImageGrab`

Installed app: `/Users/sam/Applications/ImageGrab.app`

Running app at handover:
- `ImageGrab` pid: `70136`
- Installed binary timestamp: `May 18 22:42:46 2026`

Latest verification:
- `swift test` passed on 2026-05-19 20:40.
- Test count: 37 tests, 0 failures.

## Important Context

The worktree is intentionally dirty. Do not revert unrelated changes.

Recent shipped/local features:
- Preview-window OCR / Copy Text now opens a compact result popover.
- Popover thumbnail OCR / Copy Text exists.
- Preview buttons were polished.
- Delayed capture exists with `Now`, `3s`, `5s`, `10s`.
- `Opt+G` is restored to the proven native macOS region picker path.
- `Opt+Cmd+G` remains full-screen capture.

## Code Signing / Screen Recording Permission (2026-06-01)

`./Scripts/build_app.sh` re-signs on every build. When it fell back to an **ad-hoc**
signature, the app's code identity changed each rebuild and macOS silently revoked its
Screen Recording grant — capture showed the region crosshairs but produced no image
(`could not create image from rect` in the log), no preview window, nothing saved. This
masquerades as an app bug.

Fix: `build_app.sh` now auto-detects a real codesigning identity (Apple Development,
Team `WAA9GY9XKP`) instead of ad-hoc, keeping a stable identity so the permission
persists across rebuilds. If capture silently breaks after a rebuild, check
`codesign -dvv ~/Applications/ImageGrab.app` is not `adhoc`, then re-grant Screen
Recording. See `CLAUDE.md` for the full runbook. Do not iterate with ad-hoc signing.

## Critical Regression Note

An attempted "Last-Region Recapture" implementation replaced `Opt+G` with a custom `CaptureRegionSelector`. The user reported `Opt+G` stopped working.

Fix applied:
- `Opt+G` was restored to native `screencapture -i -c`.
- The app was rebuilt and relaunched.

Do not reintroduce the custom selector into the main `Opt+G` path without manually testing the hotkey end-to-end.

Current repeat-region status:
- `CaptureRegion.swift`, `CaptureRegionSelector.swift`, and related tests exist.
- `PopoverViewModel` has `lastCaptureRegion` / repeat callback state.
- The repeat button exists in the popover, but it will remain disabled in normal use because native `screencapture -i -c` does not expose the selected rectangle back to the app.
- Treat repeat-region as unfinished/experimental.

## Changed/Untracked Areas

Notable modified files:
- `README.md`
- `Sources/ImageGrab/AnnotationOverlayView.swift`
- `Sources/ImageGrab/AppDelegate.swift`
- `Sources/ImageGrab/CaptureOverlayWindow.swift`
- `Sources/ImageGrab/ImageGrabPopoverView.swift`
- `Sources/ImageGrab/PopoverViewModel.swift`
- `Tests/ImageGrabKitTests/AnnotationOverlayViewTests.swift`

Notable new files:
- `Sources/ImageGrab/CaptureCountdownPanel.swift`
- `Sources/ImageGrab/CaptureDelay.swift`
- `Sources/ImageGrab/CaptureRegion.swift`
- `Sources/ImageGrab/CaptureRegionSelector.swift`
- `Sources/ImageGrab/OCRResultPopover.swift`
- `Sources/ImageGrab/OCRResultPresenter.swift`
- `Sources/ImageGrab/TextRecognizer.swift`
- `Tests/ImageGrabKitTests/CaptureDelayTests.swift`
- `Tests/ImageGrabKitTests/CaptureRegionTests.swift`
- `Tests/ImageGrabKitTests/OCRResultPresenterTests.swift`
- `Tests/ImageGrabKitTests/TextRecognizerTests.swift`
- `docs/ocr-copy-text-explainer.html`
- `docs/qwen-harness.md`
- `docs/upgrade-options.md`
- `tools/imagegrab_qwen/`
- `bin/imagegrab-qwen`

## Verification Commands

Use these from repo root:

```sh
swift build
swift test
./Scripts/build_app.sh
open /Users/sam/Applications/ImageGrab.app
pgrep -fl ImageGrab
stat -f '%Sm %N' /Users/sam/Applications/ImageGrab.app/Contents/MacOS/ImageGrab
```

After app relaunch, manually test:
- `Opt+G` starts native region capture.
- Esc during native region capture resets state; pressing `Opt+G` again still works.
- `Opt+Cmd+G` captures full screen.
- Delay selector applies to both hotkeys.
- Preview-window `Copy Text` opens OCR result popover.

## Recommended Next Step

Before adding more features, do a short stabilization pass:
1. Decide whether to remove the unfinished repeat-region UI/files or keep them behind a clear experimental flag.
2. Manually test `Opt+G`, `Opt+Cmd+G`, delayed capture, and preview OCR in the installed app.
3. If repeat-region is still desired, design it without replacing native `screencapture -i -c`. A safer route may be using fixed-region capture only after a separately confirmed region source, or deferring it.

## Bridge/Model Notes

Claude Code was used through the TermGrid bridge for OCR result UI and delayed capture work. The loop was: bridge to Claude, Claude bridges back, Codex reviews, patches issues, runs tests, relaunches app.

Qwen-local was tested via `tools/imagegrab_qwen`; it was useful for intent/review but unreliable for direct patching. GLM 5.1 on the M3 Ultra was also tested and then unloaded from RAM. At handover, no GLM server should be running.
