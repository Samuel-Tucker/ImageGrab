# ImageGrab — agent notes

macOS menu-bar screenshot + annotation app. SPM package: library target `ImageGrabKit`
(path `Sources/ImageGrab/`, despite the name) + executable `ImageGrab` (`Sources/ImageGrabApp/`).
Tests in `Tests/ImageGrabKitTests`.

## ⚠️ Code signing & Screen Recording permission (read before rebuilding)

`./Scripts/build_app.sh` **re-signs the app on every build.** If it falls back to an
**ad-hoc** signature, the app's code identity changes each build, and macOS silently
**revokes its Screen Recording (TCC) grant.** Symptom: the capture hotkey shows the
region crosshairs, but no preview window appears and nothing is saved — the unified
log shows `could not create image from rect`. This looks like an app bug but is a
permission failure upstream of all the app code.

Fixes already in place:
- `build_app.sh` now auto-detects a real codesigning identity (Apple Development,
  Team `WAA9GY9XKP`) when the preferred `ImageGrab Dev` identity isn't in the keychain,
  instead of falling back to ad-hoc. This keeps the code identity **stable across
  rebuilds**, so the Screen Recording grant persists.

If capture ever silently stops working after a rebuild:
1. `codesign -dvv ~/Applications/ImageGrab.app` — confirm it is **not** `Signature=adhoc`.
2. If it regressed to ad-hoc, rebuild (the script should auto-pick an identity), or pass
   `SIGN_IDENTITY="<40-char hash from: security find-identity -v -p codesigning>"`.
3. Re-grant in System Settings → Privacy & Security → Screen Recording (remove the
   stale entry, re-add ImageGrab).

Never ship a flow that relies on ad-hoc re-signing during iterative development.

## Capture hotkeys (see also handover.md "Critical Regression Note")

- `Opt+G` / `Ctrl+Cmd+G` — native region capture (`screencapture -i -c`).
- `Opt+Cmd+G` — full screen.
- Do **not** replace the native `Opt+G` path with the custom `CaptureRegionSelector`
  without manual end-to-end testing — that regressed before.

## Build / run / verify

```sh
swift build
swift test
./Scripts/build_app.sh            # builds + signs + installs to ~/Applications/ImageGrab.app
open ~/Applications/ImageGrab.app
```

The preview/annotation window only appears **after a successful capture**, so the
rearrange/annotation UI cannot be exercised headlessly — it needs a real screen capture
(and therefore working Screen Recording permission, see above).
