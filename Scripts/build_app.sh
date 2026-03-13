#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications/ImageGrab.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/ImageGrab" "$MACOS_DIR/ImageGrab"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"

# Code sign with stable identity so Screen Recording permission persists across rebuilds
codesign --force --sign "ImageGrab Dev" "$APP_DIR" && echo "Signed with ImageGrab Dev" || echo "Warning: code signing skipped (no identity)"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
