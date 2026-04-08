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
- **AI auto-rename** — Generates descriptive filenames using a local vision model (see [AI Rename](#ai-auto-rename) below)
- **Inline rename** — Click any filename to edit it; AI-named files are marked with a sparkles icon
- **Context menu** — Right-click any capture to copy path, reveal in Finder, rename, or delete

## Requirements

- macOS 13+
- Accessibility permission (for global hotkey)
- No Screen Recording permission needed when using the native macOS screenshot crosshair

## Build & Install

```sh
git clone https://github.com/Samuel-Tucker/ImageGrab.git
cd ImageGrab
./Scripts/build_app.sh
```

The build script:

- Installs `ImageGrab.app` to `~/Applications`
- Registers the app with Launch Services so it appears in Spotlight
- Installs a per-user LaunchAgent so the app starts on login
- Ad-hoc signs the app by default, or uses `IMAGEGRAB_CODESIGN_IDENTITY` if you provide a local signing identity

On first launch, ImageGrab prompts for Accessibility access and opens the correct System Settings screen.

## Usage

1. Press **Ctrl+Opt+G** (or click the camera icon in the menu bar)
2. Select a screen region with the crosshair
3. Annotate if needed — pick a tool and color from the toolbar
4. Click **Save & Copy Path** (or just **Save**)
5. Find captures in the popover grid — click thumbnails to copy paths, or drag them into other apps

Captures are stored in `~/Library/Application Support/ImageGrab/Captures/`.

If you dismiss the Accessibility prompt, open the menu bar popover and click **Enable Accessibility** to jump back to the correct settings pane.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Opt+G` | Start capture |
| `Cmd+Z` | Undo annotation |
| `Esc` | Cancel capture / dismiss text |
| `Return` | Save & Copy Path |
| `Scroll wheel` | Adjust text size (text tool) |

## AI Auto-Rename

ImageGrab can automatically rename screenshots with descriptive filenames (e.g. `api-reference-docs.png` instead of `capture-20260318-112738.png`). This is an **optional feature** that requires a local AI vision model.

### How it works

After each capture, ImageGrab sends the screenshot to a local [Ollama](https://ollama.com) vision model that looks at the image and suggests a short, descriptive name. The rename happens in the background — if no model is available, the timestamp name is kept.

### Setup

1. **Install Ollama** (if you don't have it):
   ```sh
   brew install ollama
   ```

2. **Pull the moondream model** (~1.7GB download):
   ```sh
   ollama pull moondream
   ```

3. **Make sure Ollama is running:**
   ```sh
   ollama serve
   ```
   Or launch the Ollama app — it runs in the menu bar.

That's it. ImageGrab will detect Ollama automatically on `localhost:11434`.

### Model details

| | |
|---|---|
| **Model** | [moondream](https://ollama.com/library/moondream) (1.8B params) |
| **Disk** | ~1.7 GB |
| **RAM** | ~1.1 GB (runs on GPU via Metal) |
| **Speed** | 1-3 seconds per rename |
| **Privacy** | Fully local — no images leave your machine |

The model is **not** always in memory — Ollama loads it on demand when a rename is triggered, then automatically unloads it after 5 minutes of inactivity. Any Mac with 8GB+ RAM can run moondream alongside ImageGrab without issues.

### Fallback

If Ollama is not installed or the model isn't available, ImageGrab falls back to [kimi-cli](https://github.com/anthropics/kimi-cli) (text-only, less accurate). If neither is available, files keep their timestamp names — the app works fine without AI rename.

## Tech Stack

Swift 6 · SwiftUI · AppKit · Swift Package Manager · Carbon hotkey API

## License

MIT
