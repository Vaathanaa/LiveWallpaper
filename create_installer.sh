#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

VERSION="1.2.3"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_TEMP="$PROJECT_DIR/.build_installer"

echo "========================================================"
echo "   LiveWallpaper — macOS Packaging & Installer Suite   "
echo "   Apple Silicon Native (M1/M2/M3/M4)                  "
echo "========================================================"

# 1. Ensure App and Screen Saver are compiled and ready
if [ ! -d "$PROJECT_DIR/LiveWallpaper.app" ]; then
    echo "==> LiveWallpaper.app not found. Running ./build_app.sh..."
    ./build_app.sh
fi

if [ ! -d "$PROJECT_DIR/LiveWallpaper.saver" ]; then
    echo "==> LiveWallpaper.saver not found. Running ./build_screensaver.sh..."
    ./build_screensaver.sh
fi

rm -rf "$DIST_DIR" "$BUILD_TEMP"
mkdir -p "$DIST_DIR" "$BUILD_TEMP"

# ----------------------------------------------------
# A. Build macOS Drag-and-Drop Disk Image (.dmg)
# ----------------------------------------------------
echo ""
echo "==> [1/2] Generating Distribution Disk Image (.dmg)..."
DMG_ROOT="$BUILD_TEMP/dmg_root"
mkdir -p "$DMG_ROOT"

# Copy App and Screen Saver
cp -R "$PROJECT_DIR/LiveWallpaper.app" "$DMG_ROOT/"
cp -R "$PROJECT_DIR/LiveWallpaper.saver" "$DMG_ROOT/"

# Use lightweight bundled sample loop (1MB) in distributor bundle if available
if [ -f "$PROJECT_DIR/SampleWallpaper.mp4" ]; then
    cp "$PROJECT_DIR/SampleWallpaper.mp4" "$DMG_ROOT/LiveWallpaper.saver/Contents/Resources/current_wallpaper.mp4" 2>/dev/null || true
    codesign --force --deep --sign - --options runtime "$DMG_ROOT/LiveWallpaper.saver" 2>/dev/null || true
fi

# Create symlinks for easy drag & drop
ln -s /Applications "$DMG_ROOT/Applications"
ln -s "$HOME/Library/Screen Savers" "$DMG_ROOT/Screen Savers (User)"

if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$DMG_ROOT/.VolumeIcon.icns"
    SetFile -c icnC "$DMG_ROOT/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$DMG_ROOT" 2>/dev/null || true
fi

# Add Quick Installation Guide
cat << 'EOF' > "$DMG_ROOT/QUICK_INSTALL.txt"
=============================================================
  LiveWallpaper for macOS (Apple Silicon M1/M2/M3/M4)
=============================================================

1. INSTALL APP:
   Drag "LiveWallpaper.app" into the "Applications" folder.

2. INSTALL SCREEN SAVER:
   Drag "LiveWallpaper.saver" into "Screen Savers (User)".

3. LAUNCH:
   Open /Applications/LiveWallpaper.app.
   The app lives in your top menu bar with an icon.

4. FIRST RUN NOTE:
   If macOS displays Gatekeeper notice on ad-hoc builds:
   Right-click LiveWallpaper.app -> Open -> Click "Open"
   or run in Terminal: xattr -cr /Applications/LiveWallpaper.app

Enjoy silky 120Hz ProMotion Live Wallpapers!
EOF

DMG_OUTPUT="$DIST_DIR/LiveWallpaper-${VERSION}.dmg"
rm -f "$DMG_OUTPUT"

# Compute size with headroom
DIR_SIZE_MB=$(du -sm "$DMG_ROOT" | cut -f1)
TOTAL_SIZE_MB=$((DIR_SIZE_MB + 50))
if [ "$TOTAL_SIZE_MB" -lt 50 ]; then
    TOTAL_SIZE_MB=50
fi

hdiutil create -volname "LiveWallpaper" \
    -srcfolder "$DMG_ROOT" \
    -ov -format UDZO \
    -size "${TOTAL_SIZE_MB}m" \
    "$DMG_OUTPUT"

shasum -a 256 "$DMG_OUTPUT" > "$DMG_OUTPUT.sha256"
echo "✔ Successfully created DMG: $DMG_OUTPUT"
cat "$DMG_OUTPUT.sha256"

# ----------------------------------------------------
# B. Build macOS Guided Installer Package (.pkg)
# ----------------------------------------------------
echo ""
echo "==> [2/2] Generating Guided Installer Package (.pkg)..."

PKG_PAYLOAD="$BUILD_TEMP/pkg_payload"
PKG_SCRIPTS="$BUILD_TEMP/pkg_scripts"
mkdir -p "$PKG_PAYLOAD/Applications"
mkdir -p "$PKG_PAYLOAD/Library/Screen Savers"
mkdir -p "$PKG_SCRIPTS"

cp -R "$PROJECT_DIR/LiveWallpaper.app" "$PKG_PAYLOAD/Applications/"
cp -R "$DMG_ROOT/LiveWallpaper.saver" "$PKG_PAYLOAD/Library/Screen Savers/"

# Create postinstall script
cat << 'EOF' > "$PKG_SCRIPTS/postinstall"
#!/bin/bash
set -e

# Clear Gatekeeper quarantine attributes for smooth launch
xattr -cr /Applications/LiveWallpaper.app 2>/dev/null || true
xattr -cr "/Library/Screen Savers/LiveWallpaper.saver" 2>/dev/null || true

# Register the screensaver for the current logged-in user
LOGGED_IN_USER=$(stat -f "%Su" /dev/console)
if [ -n "$LOGGED_IN_USER" ] && [ "$LOGGED_IN_USER" != "root" ]; then
    USER_HOME=$(eval echo "~$LOGGED_IN_USER")
    mkdir -p "$USER_HOME/Library/Screen Savers"
    cp -R "/Library/Screen Savers/LiveWallpaper.saver" "$USER_HOME/Library/Screen Savers/" 2>/dev/null || true
    chown -R "$LOGGED_IN_USER" "$USER_HOME/Library/Screen Savers/LiveWallpaper.saver" 2>/dev/null || true
    
    # Configure screensaver defaults for user
    sudo -u "$LOGGED_IN_USER" defaults -currentHost write com.apple.screensaver moduleDict -dict moduleName LiveWallpaper path "$USER_HOME/Library/Screen Savers/LiveWallpaper.saver" type -int 0 2>/dev/null || true
fi

exit 0
EOF

chmod +x "$PKG_SCRIPTS/postinstall"

COMPONENT_PKG="$BUILD_TEMP/LiveWallpaperComponent.pkg"
pkgbuild --root "$PKG_PAYLOAD" \
    --scripts "$PKG_SCRIPTS" \
    --identifier "com.local.LiveWallpaper.pkg" \
    --version "${VERSION}" \
    --install-location "/" \
    "$COMPONENT_PKG"

FINAL_PKG="$DIST_DIR/LiveWallpaper-Installer-${VERSION}.pkg"

# Create a clean product distribution wrapper
productbuild --package "$COMPONENT_PKG" "$FINAL_PKG"

shasum -a 256 "$FINAL_PKG" > "$FINAL_PKG.sha256"
echo "✔ Successfully created PKG: $FINAL_PKG"
cat "$FINAL_PKG.sha256"

# Cleanup temporary build directory
rm -rf "$BUILD_TEMP"

echo ""
echo "========================================================"
echo "✔ Distribution Packages Built Successfully in: $DIST_DIR"
echo "  1. Disk Image: $DMG_OUTPUT"
echo "  2. PKG Wizard: $FINAL_PKG"
echo "========================================================"
