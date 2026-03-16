# ImageGrab

A lightweight macOS menu bar app for screen captures with built-in annotation tools, AI-powered renaming, and drag-and-drop sharing.

## Screenshots

| Preview Window | Annotation Tools |
|:-:|:-:|
| ![Preview Window](Screenshots/preview-window.png) | ![Annotations](Screenshots/annotations.png) |

| Thumbnail Grid | Context Menu |
|:-:|:-:|
| ![Popover Grid](Screenshots/popover-grid.png) | ![Context Menu](Screenshots/context-menu.png) |

## Features

- **Global hotkey** — Press `Ctrl+Opt+G` from anywhere to trigger the native macOS screenshot crosshair
- **Preview before saving** — Review your capture, annotate it, then Save or Save & Copy Path
- **Annotation tools** — Draw with pen, box, arrow, and text tools across 5 color presets
- **Thumbnail grid** — Browse recent captures in a menu bar popover (up to 50)
- **Drag and drop** — Drag images from the popover directly into any app (Slack, browsers, editors, etc.)
- **AI auto-rename** — Generates short, descriptive filenames via [kimi-cli](https://github.com/anthropics/kimi-cli) (falls back to timestamps)
- **Inline rename** — Click any filename to edit it; AI-named files are marked with a sparkles icon
- **Context menu** — Right-click any capture to copy path, reveal in Finder, rename, or delete

## Requirements

- macOS 13+
- Screen Recording permission
- Accessibility permission (for global hotkey)

## Build

```sh
git clone https://github.com/Samuel-Tucker/ImageGrab.git
cd ImageGrab
./Scripts/build_app.sh
```

Installs to `~/Applications/ImageGrab.app` as a menu-bar-only app (no Dock icon).

## Usage

1. Press **Ctrl+Opt+G** (or click the camera icon in the menu bar)
2. Select a screen region with the crosshair
3. Annotate if needed — pick a tool and color from the toolbar
4. Click **Save & Copy Path** (or just **Save**)
5. Find captures in the popover grid — click thumbnails to copy paths, or drag them into other apps

Captures are stored in `~/repos/ImageGrab/captures/`.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Opt+G` | Start capture |
| `Cmd+Z` | Undo annotation |
| `Esc` | Cancel capture / dismiss text |
| `Return` | Save & Copy Path |
| `Scroll wheel` | Adjust text size (text tool) |

## Tech Stack

Swift 6 · SwiftUI · AppKit · Swift Package Manager · Carbon hotkey API

## License

MIT
