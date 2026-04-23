#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ImageGrab"
APP_DIR="${APP_DIR:-$HOME/Applications/${APP_NAME}.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-ImageGrab Dev}"
ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-0}"
REGISTER_APP="${REGISTER_APP:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.samueltucker.imagegrab}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/$CONFIGURATION/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/$APP_NAME"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
if [[ -n "$VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
fi

if [[ "$SIGN_IDENTITY" == "none" ]]; then
  echo "Skipping code signing"
elif [[ "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR" \
    && echo "Signed with $SIGN_IDENTITY (hardened runtime)" \
    || echo "Warning: code signing skipped (identity unavailable)"
else
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" \
    && echo "Signed with $SIGN_IDENTITY" \
    || echo "Warning: code signing skipped (identity unavailable)"
fi

if [[ "$REGISTER_APP" == "1" ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built $APP_DIR"
