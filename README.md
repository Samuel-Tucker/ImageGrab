# ImageGrab

macOS menu bar app for quick screen captures with AI auto-rename, thumbnail grid, and drag-and-drop to any app.

## Features

- **Global hotkey** (Ctrl+Opt+G) triggers the native macOS screenshot crosshair
- **Preview window** to review captures before saving, with Save or Save & Copy Path options
- **Thumbnail grid** in a menu bar popover — click to copy path, right-click for context menu
- **Drag and drop** images from the popover directly into Claude, browsers, Slack, or any app
- **AI auto-rename** via kimi-cli generates short descriptive filenames (falls back to timestamp)
- **Inline rename** — click any filename to edit it

## Requirements

- macOS 13+
- Accessibility permission (for global hotkey)

## Build

```sh
./Scripts/build_app.sh
```

Installs to `~/Applications/ImageGrab.app`.

## Usage

1. Click the camera icon in the menu bar, or press **Ctrl+Opt+G**
2. Select a screen region with the crosshair
3. Review the capture in the preview window — click **Save** or **Save & Copy Path**
4. Find your captures in the popover grid — click thumbnails to copy paths, or drag them into other apps

Captures are stored in `~/repos/ImageGrab/captures/`.

## Tech

Swift 6, SwiftUI, SPM, Carbon hotkey API, NSPasteboard, NSPopover.
