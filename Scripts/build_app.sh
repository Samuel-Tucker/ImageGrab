#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$HOME/Applications/ImageGrab.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_LABEL="local.imagegrab.app"
LAUNCH_AGENT_TEMPLATE="$ROOT_DIR/Support/$LAUNCH_AGENT_LABEL.plist.template"
LAUNCH_AGENT_DEST="$LAUNCH_AGENTS_DIR/$LAUNCH_AGENT_LABEL.plist"
SIGNING_IDENTITY="${IMAGEGRAB_CODESIGN_IDENTITY:-ImageGrab Dev}"
INSTALL_LAUNCH_AGENT="${IMAGEGRAB_INSTALL_LAUNCH_AGENT:-1}"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/ImageGrab" "$MACOS_DIR/ImageGrab"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"

if security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
  echo "Signed with $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - "$APP_DIR"
  echo "Signed ad-hoc (set IMAGEGRAB_CODESIGN_IDENTITY to use a stable local signing identity)"
fi

if [[ "$INSTALL_LAUNCH_AGENT" == "1" ]]; then
  mkdir -p "$LAUNCH_AGENTS_DIR"
  sed "s#__IMAGEGRAB_EXECUTABLE__#$MACOS_DIR/ImageGrab#g" "$LAUNCH_AGENT_TEMPLATE" > "$LAUNCH_AGENT_DEST"
  plutil -lint "$LAUNCH_AGENT_DEST" >/dev/null

  USER_ID="$(id -u)"
  launchctl print "gui/$USER_ID" >/dev/null 2>&1 || USER_ID=""

  if [[ -n "$USER_ID" ]]; then
    launchctl bootout "gui/$USER_ID/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    if pgrep -x ImageGrab >/dev/null 2>&1; then
      echo "Installed launch agent at $LAUNCH_AGENT_DEST"
      echo "ImageGrab is already running; the new login item will be used on next login."
    elif launchctl bootstrap "gui/$USER_ID" "$LAUNCH_AGENT_DEST" >/dev/null 2>&1; then
      echo "Installed launch agent at $LAUNCH_AGENT_DEST"
    else
      echo "Installed launch agent at $LAUNCH_AGENT_DEST (will load on next login)"
    fi
  else
    echo "Installed launch agent at $LAUNCH_AGENT_DEST (load it after logging into a GUI session)"
  fi
fi

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"
