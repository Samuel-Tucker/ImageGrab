#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ImageGrab"
VERSION_INPUT="${1:-${VERSION:-}}"
if [[ -z "$VERSION_INPUT" ]]; then
  VERSION_INPUT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Support/Info.plist")"
fi

VERSION="${VERSION_INPUT#v}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-$(git rev-list --count HEAD)}}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/$VERSION}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macOS.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
DMG_STAGE_DIR="$DIST_DIR/dmg-stage"
SIGN_IDENTITY="${SIGN_IDENTITY:-none}"
NOTARIZE="${NOTARIZE:-0}"
APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-}"
VERIFY_RELEASE_ASSETS="${VERIFY_RELEASE_ASSETS:-1}"

if [[ "$NOTARIZE" == "1" && "$SIGN_IDENTITY" == "none" ]]; then
  echo "NOTARIZE=1 requires SIGN_IDENTITY to be set to a Developer ID Application certificate" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${TEMP_KEY_FILE:-}" && -f "$TEMP_KEY_FILE" ]]; then
    rm -f "$TEMP_KEY_FILE"
  fi
}
trap cleanup EXIT

notary_auth_args() {
  if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    print -r -- "--keychain-profile"
    print -r -- "$NOTARYTOOL_PROFILE"
    return
  fi

  if [[ -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_ISSUER_ID:-}" ]]; then
    echo "Missing notary credentials. Set NOTARYTOOL_PROFILE or APPLE_API_KEY_ID + APPLE_API_ISSUER_ID." >&2
    exit 1
  fi

  if [[ -z "$APPLE_API_KEY_PATH" ]]; then
    if [[ -z "${APPLE_API_PRIVATE_KEY:-}" ]]; then
      echo "Missing Apple API private key. Set APPLE_API_PRIVATE_KEY or APPLE_API_KEY_PATH." >&2
      exit 1
    fi
    TEMP_KEY_FILE="$DIST_DIR/AuthKey_${APPLE_API_KEY_ID}.p8"
    print -rn -- "${APPLE_API_PRIVATE_KEY}" > "$TEMP_KEY_FILE"
    APPLE_API_KEY_PATH="$TEMP_KEY_FILE"
  fi

  print -r -- "--key"
  print -r -- "$APPLE_API_KEY_PATH"
  print -r -- "--key-id"
  print -r -- "${APPLE_API_KEY_ID}"
  print -r -- "--issuer"
  print -r -- "${APPLE_API_ISSUER_ID}"
}

notarize_file() {
  local file_path="$1"
  local -a auth_args
  auth_args=("${(@f)$(notary_auth_args)}")
  xcrun notarytool submit "$file_path" "${auth_args[@]}" --wait
}

create_zip() {
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent --sequesterRsrc "$APP_DIR" "$ZIP_PATH"
}

create_dmg() {
  rm -rf "$DMG_STAGE_DIR"
  mkdir -p "$DMG_STAGE_DIR"
  cp -R "$APP_DIR" "$DMG_STAGE_DIR/"
  ln -s /Applications "$DMG_STAGE_DIR/Applications"
  rm -f "$DMG_PATH"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE_DIR" \
    -format UDZO \
    "$DMG_PATH" \
    >/dev/null
  rm -rf "$DMG_STAGE_DIR"
}

verify_release_assets() {
  if [[ "$VERIFY_RELEASE_ASSETS" != "1" ]]; then
    return
  fi

  local verify_dir="$DIST_DIR/verify"
  local zip_extract_dir="$verify_dir/zip"
  local mount_dir="$verify_dir/dmg"
  local verify_status=0

  rm -rf "$verify_dir"
  mkdir -p "$zip_extract_dir" "$mount_dir"

  shasum -a 256 -c "$DIST_DIR/SHA256SUMS" >/dev/null

  ditto -x -k "$ZIP_PATH" "$zip_extract_dir"
  if [[ ! -d "$zip_extract_dir/$APP_NAME.app" ]]; then
    echo "Release verification failed: zip does not contain $APP_NAME.app" >&2
    verify_status=1
  else
    codesign --verify --deep --strict "$zip_extract_dir/$APP_NAME.app" || verify_status=$?
  fi

  if [[ "$verify_status" == "0" ]]; then
    hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
    if [[ ! -d "$mount_dir/$APP_NAME.app" ]]; then
      echo "Release verification failed: dmg does not contain $APP_NAME.app" >&2
      verify_status=1
    elif [[ ! -L "$mount_dir/Applications" ]]; then
      echo "Release verification failed: dmg does not include Applications shortcut" >&2
      verify_status=1
    else
      codesign --verify --deep --strict "$mount_dir/$APP_NAME.app" || verify_status=$?
    fi
    hdiutil detach "$mount_dir" >/dev/null || true
  fi

  rm -rf "$verify_dir"

  if [[ "$verify_status" != "0" ]]; then
    exit "$verify_status"
  fi

  echo "Verified release assets"
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

APP_DIR="$APP_DIR" \
REGISTER_APP=0 \
CONFIGURATION=release \
SIGN_IDENTITY="$SIGN_IDENTITY" \
ENABLE_HARDENED_RUNTIME=1 \
VERSION="$VERSION" \
BUILD_NUMBER="$BUILD_NUMBER" \
"$ROOT_DIR/Scripts/build_app.sh"

create_zip

if [[ "$NOTARIZE" == "1" ]]; then
  notarize_file "$ZIP_PATH"
  xcrun stapler staple "$APP_DIR"
  create_zip
fi

create_dmg

if [[ "$SIGN_IDENTITY" != "none" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  notarize_file "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
fi

shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$DIST_DIR/SHA256SUMS"
verify_release_assets

echo "Created release assets:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $DIST_DIR/SHA256SUMS"
