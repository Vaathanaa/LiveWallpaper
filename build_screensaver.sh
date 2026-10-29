#!/bin/bash
set -e

PROJECT_DIR="/Users/vaathanaa007/.gemini/antigravity/scratch/VideoBackdrop"
SAVER_BUNDLE="$HOME/Library/Screen Savers/VideoBackdrop.saver"

echo "==> Compiling VideoBackdrop.saver (Screen Saver)..."
mkdir -p "$SAVER_BUNDLE/Contents/MacOS"

swiftc -emit-library "$PROJECT_DIR/ScreenSaver/VideoBackdropScreenSaverView.swift" \
  -module-name VideoBackdropScreenSaver \
  -framework ScreenSaver \
  -framework AVFoundation \
  -framework AppKit \
  -target arm64-apple-macos13.0 \
  -O \
  -o "$SAVER_BUNDLE/Contents/MacOS/VideoBackdropScreenSaver"

cat << 'EOF' > "$SAVER_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VideoBackdropScreenSaver</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.VideoBackdrop.ScreenSaver</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VideoBackdrop</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>VideoBackdropScreenSaverView</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$SAVER_BUNDLE"
echo "==> VideoBackdrop.saver built and signed successfully at $SAVER_BUNDLE"
