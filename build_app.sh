#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "==> Building LiveWallpaper (arm64, Apple Silicon M1/M2/M3/M4)..."
swift build -c release

BIN_DIR="$(swift build --show-bin-path -c release)"
BIN_PATH="$BIN_DIR/LiveWallpaper"
APP_DIR="$PROJECT_DIR/LiveWallpaper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Packaging into macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/LiveWallpaper"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

ENTITLEMENTS="$PROJECT_DIR/Resources/LiveWallpaper.entitlements"

echo "==> Applying Apple Hardened Runtime signature with entitlements..."
if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --deep --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP_DIR"
else
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Installing to /Applications/LiveWallpaper.app..."
rm -rf /Applications/LiveWallpaper.app
cp -R "$APP_DIR" /Applications/LiveWallpaper.app

echo "==> Build successful! LiveWallpaper.app is ready in /Applications and at:"
echo "    $APP_DIR"
