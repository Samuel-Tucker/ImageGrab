# ImageGrab

A lightweight macOS menu bar app for fast native screenshots, quick markup, OCR, and drag-and-drop sharing.

## Screenshots

| Preview Window | Annotation Tools |
|:-:|:-:|
| ![Preview Window](Screenshots/preview-window.png) | ![Annotations](Screenshots/annotations.png) |

| Thumbnail Grid | Context Menu |
|:-:|:-:|
| ![Popover Grid](Screenshots/popover-grid.png) | ![Context Menu](Screenshots/context-menu.png) |

## Features

- **Global hotkeys** — Press `Ctrl+Cmd+G` for region capture or `Opt+Cmd+G` for full-screen capture. `Opt+G` is still attempted as a legacy region shortcut on systems that do not reserve it.
- **Popover capture buttons** — Start region or full-screen capture from the menu bar popover if a global shortcut is unavailable
- **Delayed capture** — Choose `Now`, `3s`, `5s`, or `10s` from the menu bar popover before your next capture
- **Preview before saving** — Review every capture before it is written to disk
- **Copy Text / OCR** — Extract text from a preview or saved capture using Apple Vision, then copy it to the clipboard
- **Annotation tools** — Pen, box, arrow, and text with color presets plus a text background picker
- **Movable annotations** — Click existing text, boxes, arrows, or pen strokes to reposition them
- **Editable text markup** — Click text annotations to reopen editing, then adjust font size with `Cmd+=`, `Cmd+-`, or the scroll wheel
- **Quick view panel** — Hover a thumbnail and click the eye icon for a floating larger preview
- **Thumbnail grid** — Browse up to 50 recent captures from the menu bar popover
- **Rename and edit later** — Rename saved captures inline or reopen them for annotation edits
- **Drag and drop** — Drag captures into chat apps, Gmail, Slack, Discord, browsers, Finder, terminals, and Electron apps
- **Context menu** — Preview, copy path, copy text, edit annotations, reveal in Finder, rename, or delete any capture
- **Compatible output** — Saves PNG files for reliable drag-and-drop uploads into chat, email, and browser apps

## Requirements

- macOS 13+
- macOS screenshot permissions if prompted by the system

ImageGrab uses the built-in macOS screenshot tool for region and full-screen capture.

## Install

### Manual install

The lowest-friction manual install path is the latest GitHub Release:

`https://github.com/Samuel-Tucker/ImageGrab/releases/latest`

Download `ImageGrab-<version>.dmg`, open it, then drag `ImageGrab.app` into `/Applications`.

The release also includes `ImageGrab-<version>-macOS.zip` for direct extraction and `SHA256SUMS` for checksum verification.

### Agent/source install

For a coding agent or a developer building from source:

```sh
git clone https://github.com/Samuel-Tucker/ImageGrab.git
cd ImageGrab
./Scripts/build_app.sh
open "$HOME/Applications/ImageGrab.app"
```

The build script creates `~/Applications/ImageGrab.app`, registers it with Launch Services, and attempts to codesign it with the local `ImageGrab Dev` identity if that certificate exists. If that identity is unavailable, it applies an ad-hoc app signature so macOS sees a coherent bundle identity.

### Current macOS note

The smoothest public install requires Developer ID signing and notarization. If a release is not signed/notarized, macOS may warn on first launch. In that case:

1. Move `ImageGrab.app` to `/Applications`
2. Right-click the app and choose **Open**
3. Confirm the warning once

If macOS still blocks launch, remove quarantine manually:

```sh
xattr -dr com.apple.quarantine /Applications/ImageGrab.app
```

## Build

Use this when you want a local development build rather than a GitHub Release install:

```sh
./Scripts/build_app.sh
```

For a non-destructive review build, point `APP_DIR` somewhere temporary:

```sh
APP_DIR=/tmp/ImageGrab.app ./Scripts/build_app.sh
open /tmp/ImageGrab.app
```

To build unsigned/no-Developer-ID release assets for local testing:

```sh
DIST_DIR=/tmp/imagegrab-release SIGN_IDENTITY=none ./Scripts/build_release_assets.sh 0.1.0
```

That produces an ad-hoc signed `.zip`, `.dmg`, and `SHA256SUMS`. Gatekeeper can still warn or reject unsigned, unnotarized downloads from the internet; Developer ID signing and notarization are required for the smoothest public install.

Release builds smoke-check the zip, DMG, app signature, Applications shortcut, and checksum file by default. Set `VERIFY_RELEASE_ASSETS=0` only when debugging the packaging script itself.

## Local Qwen Harness

For local model experiments, this repo includes an ImageGrab-specific Qwen wrapper:

```sh
bin/imagegrab-qwen status
bin/imagegrab-qwen plan "Add Copy Text to the preview window"
bin/imagegrab-qwen patch "Add Copy Text to the preview window"
bin/imagegrab-qwen review
```

It expects the local Qwen 30B coder server from the Brain harness on port `18081`,
gathers ImageGrab-specific file context, and checks returned patches with
`git apply --check`. It does not apply model patches automatically. See
[docs/qwen-harness.md](docs/qwen-harness.md).

## Usage

1. Press `Ctrl+Cmd+G` for a region capture or `Opt+Cmd+G` for a full-screen capture, or use the `Region` / `Full Screen` buttons in the menu bar popover.
2. For region captures, select a screen region with the native macOS crosshair.
3. If you need a menu, tooltip, or hover state, choose a `3s`, `5s`, or `10s` delay from the popover first.
4. Annotate in the preview window if needed, or click `Copy Text` to extract OCR text from the capture.
5. Click `Save` or `Save & Copy Image`.
6. Use the menu bar popover to preview, copy paths, copy text, rename, edit, delete, or drag captures into other apps.

Captures are stored in `~/Library/Application Support/ImageGrab/Captures/` for fresh installs. Existing local development installs that already have `~/repos/ImageGrab/captures/` keep using that legacy folder.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Cmd+G` | Start region capture |
| `Opt+G` | Legacy region capture where macOS/input sources allow it |
| `Opt+Cmd+G` | Start full-screen capture |
| `Cmd+Z` | Undo the last committed annotation |
| `Cmd+Shift+Z` | Redo the last undone annotation |
| `Esc` | Cancel capture, clear selection, or finish text editing |
| `Return` | Save & Copy Image from the preview window |
| `Cmd+=` / `Cmd+-` | Increase or decrease selected text size |
| `Scroll wheel` | Adjust text size while using or editing the text tool |

## Tech Stack

Swift 6 · SwiftUI · AppKit · Swift Package Manager · Carbon hotkey API

## Releasing

Maintainers can build release artifacts with:

```sh
./Scripts/build_release_assets.sh v0.1.0
```

With Apple credentials configured, the workflow signs and notarizes the app. Without them, it still publishes ad-hoc signed `.zip` and `.dmg` assets from version tags with first-launch notes. Full setup details are in [docs/releasing.md](docs/releasing.md).

## License

MIT
