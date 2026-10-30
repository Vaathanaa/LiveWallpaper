#!/usr/bin/env bash
set -e

# ==============================================================================
#  LiveWallpaper 1-Line Web & Local Installer for macOS (Apple Silicon M1-M4)
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/Vaathanaa/LiveWallpaper/main/install.sh | bash
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

echo -e "${CYAN}"
cat << "EOF"
  _      _           __          __   _ _                                
 | |    (_)         \ \        / /  | | |                               
 | |     _Apache__   \ \  /\  / /_ _| | |_ __   __ _ _ __   ___ _ __    
 | |    | \ \ / / _ \ \ \/  \/ / _` | | | '_ \ / _` | '_ \ / _ \ '__|   
 | |____| |\ V /  __/  \  /\  / (_| | | | |_) | (_| | |_) |  __/ |      
 |______|_| \_/ \___|   \/  \/ \__,_|_|_| .__/ \__,_| .__/ \___|_|      
                                        | |         | |                 
                                        |_|         |_|                 
EOF
echo -e "${RESET}"
echo -e "${BOLD}⚡ 120Hz ProMotion Live Wallpaper & Aerial Screen Saver for macOS${RESET}\n"

# 1. Architecture & OS check
ARCH=$(uname -m)
OS=$(uname -s)

if [ "$OS" != "Darwin" ]; then
    echo -e "${RED}✘ Error: LiveWallpaper requires macOS.${RESET}"
    exit 1
fi

if [ "$ARCH" != "arm64" ]; then
    echo -e "${YELLOW}⚠ Warning: LiveWallpaper is optimized for Apple Silicon (M1/M2/M3/M4). Running on ${ARCH}.${RESET}"
fi

REPO="Vaathanaa/LiveWallpaper"
TEMP_DIR=$(mktemp -d -t livewallpaper_install_XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${BLUE}==> Checking installation sources...${RESET}"

# If already inside a cloned LiveWallpaper directory, build directly
if [ -f "./build_app.sh" ] && [ -d "./Sources" ]; then
    echo -e "${GREEN}✔ Detected local repository source.${RESET}"
    ./build_app.sh
    ./build_screensaver.sh
else
    echo -e "${BLUE}==> Fetching latest release from GitHub (${REPO})...${RESET}"
    
    # Try downloading latest release DMG or PKG
    LATEST_RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" || true)
    DMG_URL=$(echo "$LATEST_RELEASE_JSON" | grep "browser_download_url.*\.dmg" | cut -d '"' -f 4 | head -n 1)
    
    if [ -n "$DMG_URL" ]; then
        echo -e "${BLUE}==> Downloading ${DMG_URL}...${RESET}"
        curl -L "$DMG_URL" -o "$TEMP_DIR/LiveWallpaper.dmg"
        
        echo -e "${BLUE}==> Mounting disk image...${RESET}"
        MOUNT_DIR=$(hdiutil attach "$TEMP_DIR/LiveWallpaper.dmg" -nobrowse | grep "/Volumes" | awk -F'\t' '{print $NF}' | tr -d '\n')
        
        echo -e "${BLUE}==> Installing LiveWallpaper.app to /Applications...${RESET}"
        killall LiveWallpaper 2>/dev/null || true
        rm -rf /Applications/LiveWallpaper.app
        cp -R "$MOUNT_DIR/LiveWallpaper.app" /Applications/
        
        if [ -d "$MOUNT_DIR/LiveWallpaper.saver" ]; then
            echo -e "${BLUE}==> Installing Screen Saver...${RESET}"
            mkdir -p "$HOME/Library/Screen Savers"
            rm -rf "$HOME/Library/Screen Savers/LiveWallpaper.saver"
            cp -R "$MOUNT_DIR/LiveWallpaper.saver" "$HOME/Library/Screen Savers/"
        fi
        
        hdiutil detach "$MOUNT_DIR" -quiet || true
    else
        echo -e "${YELLOW}==> No prebuilt binary found on Releases. Compiling from source...${RESET}"
        git clone --depth 1 "https://github.com/${REPO}.git" "$TEMP_DIR/LiveWallpaper"
        cd "$TEMP_DIR/LiveWallpaper"
        ./build_app.sh
        ./build_screensaver.sh
        cd - > /dev/null
    fi
fi

# 2. Gatekeeper & Permissions setup
echo -e "${BLUE}==> Clearing macOS Gatekeeper quarantine flags...${RESET}"
xattr -cr /Applications/LiveWallpaper.app 2>/dev/null || true
xattr -cr "$HOME/Library/Screen Savers/LiveWallpaper.saver" 2>/dev/null || true

# 3. Screen saver defaults setup
echo -e "${BLUE}==> Registering Screen Saver...${RESET}"
SAVER_PATH="$HOME/Library/Screen Savers/LiveWallpaper.saver"
if [ -d "$SAVER_PATH" ]; then
    defaults -currentHost write com.apple.screensaver moduleDict -dict moduleName LiveWallpaper path "$SAVER_PATH" type -int 0 2>/dev/null || true
    
    # Configure System Events
    osascript -e 'tell application "System Events" to set current screen saver to screen saver "LiveWallpaper"' 2>/dev/null || true
fi

# 4. Launch LiveWallpaper
echo -e "${GREEN}==> Launching LiveWallpaper.app...${RESET}"
open /Applications/LiveWallpaper.app

echo -e "\n${GREEN}================================================================${RESET}"
echo -e "${BOLD}${GREEN}✔ LiveWallpaper installed successfully to /Applications!${RESET}"
echo -e "${CYAN}• Menu Bar Icon:${RESET} Look for the play icon in your macOS top menu bar."
echo -e "${CYAN}• Screen Saver:${RESET} Fully synced and ready in System Settings > Wallpaper."
echo -e "${CYAN}• Star on GitHub:${RESET} https://github.com/${REPO}"
echo -e "${GREEN}================================================================${RESET}\n"
