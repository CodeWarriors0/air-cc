#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${ROOT_DIR:?}/dist"
APP_BUNDLE="${DIST_DIR:?}/air-cc.app"
ICONSET_DIR="${DIST_DIR:?}/AppIcon.iconset"

echo "==> [1/4] Running unit tests..."
swift run --package-path "$ROOT_DIR" AirCCSelfTest

echo "==> [2/4] Building Release binary..."
swift build -c release --product air-cc --package-path "$ROOT_DIR"
BIN_PATH="$(swift build -c release --product air-cc --package-path "$ROOT_DIR" --show-bin-path)/air-cc"

echo "==> [3/4] Assembling air-cc.app bundle..."
rm -rf "${APP_BUNDLE:?}" "${ICONSET_DIR:?}"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/air-cc"
chmod +x "$APP_BUNDLE/Contents/MacOS/air-cc"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET_DIR:?}"

echo "==> [4/4] Ad-hoc signing air-cc.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build succeeded: $APP_BUNDLE"
