# ImageGrab

A lightweight macOS menu bar app for fast native screenshots, quick markup, and drag-and-drop sharing.

## Screenshots

| Preview Window | Annotation Tools |
|:-:|:-:|
| ![Preview Window](Screenshots/preview-window.png) | ![Annotations](Screenshots/annotations.png) |

| Thumbnail Grid | Context Menu |
|:-:|:-:|
| ![Popover Grid](Screenshots/popover-grid.png) | ![Context Menu](Screenshots/context-menu.png) |

## Features

- **Global hotkeys** — Press `Opt+G` for a region capture or `Opt+Cmd+G` for a full-screen capture
- **Preview before saving** — Review every capture before it is written to disk
- **Annotation tools** — Pen, box, arrow, and text with color presets plus a text background picker
- **Movable annotations** — Click existing text, boxes, arrows, or pen strokes to reposition them
- **Editable text markup** — Click text annotations to reopen editing, then adjust font size with `Cmd+=`, `Cmd+-`, or the scroll wheel
- **Quick view panel** — Hover a thumbnail and click the eye icon for a floating larger preview
- **Thumbnail grid** — Browse up to 50 recent captures from the menu bar popover
- **Drag and drop** — Drag captures into chat apps, Gmail, Slack, Discord, browsers, Finder, terminals, and Electron apps
- **Context menu** — Preview, copy path, reveal in Finder, or delete any capture
- **Compatible output** — Saves PNG files for reliable drag-and-drop uploads into chat, email, and browser apps

## Requirements

- macOS 13+
- macOS screenshot permissions if prompted by the system

ImageGrab uses the built-in macOS screenshot tool for region and full-screen capture.

## Install

For end users, the simplest install path is a GitHub Release download:

- `.zip` for direct app extraction
- `.dmg` for drag-to-Applications install

Release artifacts are published at:

`https://github.com/Samuel-Tucker/ImageGrab/releases`

### Current macOS note

Without Apple Developer signing/notarization, macOS may warn on first launch. The simplest path is:

1. Download the `.dmg`
2. Drag `ImageGrab.app` into `/Applications`
3. Right-click the app and choose **Open** once

If macOS still blocks launch, remove quarantine manually:

```sh
xattr -dr com.apple.quarantine /Applications/ImageGrab.app
```

## Build

```sh
git clone https://github.com/Samuel-Tucker/ImageGrab.git
cd ImageGrab
./Scripts/build_app.sh
```

The build script creates `~/Applications/ImageGrab.app`, registers it with Launch Services, and attempts to codesign it with the local `ImageGrab Dev` identity if that certificate exists. If that identity is unavailable, it applies an ad-hoc app signature so macOS sees a coherent bundle identity.

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

## Usage

1. Press `Opt+G` for a region capture or `Opt+Cmd+G` for a full-screen capture.
2. For region captures, select a screen region with the native macOS crosshair.
3. Annotate in the preview window if needed.
4. Click `Save` or `Save & Copy Path`.
5. Use the menu bar popover to preview, copy paths, or drag captures into other apps.

Captures are stored in `~/Library/Application Support/ImageGrab/Captures/` for fresh installs. Existing local development installs that already have `~/repos/ImageGrab/captures/` keep using that legacy folder.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Opt+G` | Start region capture |
| `Opt+Cmd+G` | Start full-screen capture |
| `Cmd+Z` | Undo the last committed annotation |
| `Esc` | Cancel capture, clear selection, or finish text editing |
| `Return` | Save & Copy Path from the preview window |
| `Cmd+=` / `Cmd+-` | Increase or decrease selected text size |
| `Scroll wheel` | Adjust text size while using or editing the text tool |

## Tech Stack

Swift 6 · SwiftUI · AppKit · Swift Package Manager · Carbon hotkey API

## Releasing

Maintainers can build release artifacts with:

```sh
./Scripts/build_release_assets.sh v0.1.0
```

With Apple credentials configured, the workflow signs and notarizes the app. Without them, it still publishes usable unsigned `.zip` and `.dmg` assets from version tags. Full setup details are in [docs/releasing.md](docs/releasing.md).

## License

MIT
