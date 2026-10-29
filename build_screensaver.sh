#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAVER_BUNDLE="$HOME/Library/Screen Savers/LiveWallpaper.saver"

echo "==> Compiling LiveWallpaper.saver (Native Screen Saver)..."
mkdir -p "$SAVER_BUNDLE/Contents/MacOS"

swiftc -emit-library "$PROJECT_DIR/ScreenSaver/LiveWallpaperScreenSaverView.swift" \
  -module-name LiveWallpaperScreenSaver \
  -framework ScreenSaver \
  -framework AVFoundation \
  -framework AppKit \
  -target arm64-apple-macos13.0 \
  -O \
  -o "$SAVER_BUNDLE/Contents/MacOS/LiveWallpaperScreenSaver"

cat << 'EOF' > "$SAVER_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LiveWallpaperScreenSaver</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.LiveWallpaper.ScreenSaver</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LiveWallpaper</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>LiveWallpaperScreenSaverView</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - --options runtime "$SAVER_BUNDLE"
rm -rf "$PROJECT_DIR/LiveWallpaper.saver"
cp -R "$SAVER_BUNDLE" "$PROJECT_DIR/LiveWallpaper.saver"
echo "==> LiveWallpaper.saver built and signed successfully at $SAVER_BUNDLE"
