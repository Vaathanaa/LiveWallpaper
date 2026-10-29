#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "==> Building VideoBackdrop (arm64, Apple Silicon M1/M2/M3/M4)..."
swift build -c release

BIN_DIR="$(swift build --show-bin-path -c release)"
BIN_PATH="$BIN_DIR/VideoBackdrop"
APP_DIR="$PROJECT_DIR/VideoBackdrop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Packaging into macOS App Bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/VideoBackdrop"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "==> Applying ad-hoc code signature for local execution..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Build successful! App bundle ready at:"
echo "    $APP_DIR"
