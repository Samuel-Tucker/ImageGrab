#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_INPUT="${1:-}"

if [[ -z "$VERSION_INPUT" ]]; then
  echo "usage: $0 <version> [zip-path]" >&2
  exit 1
fi

VERSION="${VERSION_INPUT#v}"
ZIP_PATH="${2:-$ROOT_DIR/dist/$VERSION/ImageGrab-${VERSION}-macOS.zip}"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "zip artifact not found: $ZIP_PATH" >&2
  exit 1
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

cat <<EOF
cask "imagegrab" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/Samuel-Tucker/ImageGrab/releases/download/v#{version}/ImageGrab-#{version}-macOS.zip"
  name "ImageGrab"
  desc "macOS menu bar app for screenshots, markup, and drag-and-drop sharing"
  homepage "https://github.com/Samuel-Tucker/ImageGrab"

  depends_on macos: ">= :ventura"

  app "ImageGrab.app"
end
EOF
