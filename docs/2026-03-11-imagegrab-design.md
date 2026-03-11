# ImageGrab Design Spec

## Purpose
macOS menu bar app to capture images from websites, save to a folder, show thumbnails with quick copy-path and AI auto-rename.

## Menu Bar
- Icon: `camera.viewfinder` SF Symbol, template mode
- Badge dot when new uncategorized images exist

## Global Hotkey
- Ctrl+Opt+G to capture

## Capture Flow
1. User presses Ctrl+Opt+G
2. App reads image from clipboard (user copies image from browser first with right-click > Copy Image, then presses hotkey)
3. Image saved to `~/repos/ImageGrab/captures/` with timestamp filename
4. AI auto-rename fires async via `kimi-cli --quiet --no-thinking -p "Describe this image in 2-4 words for a filename. Only output the filename, no extension. Use kebab-case."` with the image path
5. File renamed silently; fallback to timestamp name if kimi times out (5s)

## Dropdown (NSPopover)
- Header: "ImageGrab" + capture count
- Grid: 2 columns of 60x60px thumbnails, 6px corner radius, max 12 recent
- Each thumbnail shows:
  - Image preview (aspect-fill, clipped)
  - AI-generated name below (11pt, secondary color)
  - `sparkles` icon if AI-named
- Click thumbnail → copy full path to clipboard, brief green flash
- Right-click → context menu: Reveal in Finder, Edit Name, Delete, Copy Image
- Click name text → inline editable field for rename
- Footer: "Open Captures Folder" + "Clear All"

## AI Rename Engine
- Tool: `kimi-cli --quiet --no-thinking -p "<prompt>"`
- Timeout: 5 seconds
- Fallback: keep timestamp name (e.g., `capture-20260311-121530.png`)
- Note: kimi-cli cannot process images directly. Rename will use clipboard text context if available, otherwise timestamp only. Future: integrate vision model when ollama is installed.

## Storage
- Captures dir: `~/repos/ImageGrab/captures/`
- Metadata: `~/repos/ImageGrab/captures/.metadata.json` (maps filename → original name, AI name, timestamp)

## Tech
- Swift 6, macOS 13+, SPM
- `NSStatusItem` + `NSPopover` + SwiftUI for popover content
- `Carbon` hotkey API
- `NSPasteboard` to read images from clipboard
- `Process` to shell out to kimi-cli
- `LSUIElement = true`
