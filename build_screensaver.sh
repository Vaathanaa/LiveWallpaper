#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAVER_BUNDLE="$HOME/Library/Screen Savers/LiveWallpaper.saver"
LEGACY_BUNDLE="$HOME/Library/Screen Savers/VideoBackdrop.saver"

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
    <string>1.2.0</string>
    <key>CFBundleVersion</key>
    <string>1.2.0</string>
    <key>NSPrincipalClass</key>
    <string>LiveWallpaperScreenSaverView</string>
</dict>
</plist>
EOF

mkdir -p "$SAVER_BUNDLE/Contents/Resources"
mkdir -p "$HOME/Movies/LiveWallpaper"
if [ -f "$HOME/Library/Application Support/LiveWallpaper/current_wallpaper.mp4" ]; then
  cp "$HOME/Library/Application Support/LiveWallpaper/current_wallpaper.mp4" "$SAVER_BUNDLE/Contents/Resources/current_wallpaper.mp4"
  cp "$HOME/Library/Application Support/LiveWallpaper/current_wallpaper.mp4" "$HOME/Movies/LiveWallpaper/current_wallpaper.mp4"
fi
if [ -f "$HOME/Library/Application Support/LiveWallpaper/lockscreen_poster.jpg" ]; then
  cp "$HOME/Library/Application Support/LiveWallpaper/lockscreen_poster.jpg" "$HOME/Movies/LiveWallpaper/lockscreen_poster.jpg"
fi

codesign --force --deep --sign - --options runtime "$SAVER_BUNDLE"
rm -rf "$PROJECT_DIR/LiveWallpaper.saver"
cp -R "$SAVER_BUNDLE" "$PROJECT_DIR/LiveWallpaper.saver"

# Duplicate to VideoBackdrop.saver so whichever name macOS looks for, it works
rm -rf "$LEGACY_BUNDLE"
cp -R "$SAVER_BUNDLE" "$LEGACY_BUNDLE"

# Register in macOS currentHost screensaver preferences with explicit integer type
defaults -currentHost write com.apple.screensaver moduleDict -dict moduleName LiveWallpaper path "$SAVER_BUNDLE" type -int 0

echo "==> LiveWallpaper.saver built and registered successfully at $SAVER_BUNDLE"
