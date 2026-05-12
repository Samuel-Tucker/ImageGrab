# ImageGrab Design Spec

Historical note: this was the initial product sketch. The current app uses `Opt+G`
for region capture and `Opt+Cmd+G` for full-screen capture, and no longer includes
rename or auto-rename behavior.

## Purpose
macOS menu bar app to capture images, save to a folder, show thumbnails, preview captures, copy file paths, and drag captures into chat apps, email, browsers, terminals, and other apps.

## Menu Bar
- Icon: `camera.viewfinder` SF Symbol, template mode
- Badge dot when new uncategorized images exist

## Global Hotkey
- Opt+G to capture region
- Opt+Cmd+G to capture full screen

## Capture Flow
1. User presses Opt+G or Opt+Cmd+G
2. App triggers the native macOS screenshot shortcut to capture to clipboard
3. User reviews and optionally annotates the capture in the preview window
4. Image is saved to `~/repos/ImageGrab/captures/` with a timestamp filename
5. User can copy the file path or drag the saved file into another app

## Dropdown (NSPopover)
- Header: "ImageGrab" + capture count
- Grid: 2 columns of 60x60px thumbnails, 6px corner radius, max 12 recent
- Each thumbnail shows:
  - Image preview (aspect-fill, clipped)
  - Timestamp filename below (11pt, secondary color)
  - Always-visible Preview and Copy Path buttons
- Right-click → context menu: Preview, Copy Path, Reveal in Finder, Delete
- Footer: "Open Captures Folder" + "Clear All"

## Storage
- Captures dir: fresh installs use `~/Library/Application Support/ImageGrab/Captures/`; legacy local dev installs can continue using `~/repos/ImageGrab/captures/`
- Metadata: `~/repos/ImageGrab/captures/.metadata.json`

## Tech
- Swift 6, macOS 13+, SPM
- `NSStatusItem` + `NSPopover` + SwiftUI for popover content
- `Carbon` hotkey API
- `NSPasteboard` to read images from clipboard
- `LSUIElement = true`
