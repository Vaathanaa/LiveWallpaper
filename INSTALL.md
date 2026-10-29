# Installation Guide

This guide details how to download, build, and install **LiveWallpaper** on your Mac into `/Applications`.

---

## 📋 System Requirements
- **Hardware**: Any Mac with Apple Silicon (**M1, M2, M3, M4** — Base, Pro, Max, or Ultra).
- **macOS Version**: macOS 13.0 (Ventura), macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later.
- **Xcode / Command Line Tools**: Xcode 15+ or Command Line Tools installed (`xcode-select --install`).

---

## 🚀 Installation Options

### Option 1: Install via Homebrew Cask

```bash
# Clone the repository
git clone https://github.com/Vaathanaa/LiveWallpaper.git
cd LiveWallpaper

# Install via Homebrew Cask formula
brew install --cask ./Casks/livewallpaper.rb
```

---

### Option 2: Automatic 1-Click Build & Install to `/Applications`

Open **Terminal** and run:

```bash
# 1. Clone the repository
git clone https://github.com/Vaathanaa/LiveWallpaper.git
cd LiveWallpaper

# 2. Run the automated build and installation script
./build_app.sh
```

The script will automatically:
1. Compile the native Apple Silicon binary with release optimizations (`swift build -c release`).
2. Package the macOS `.app` bundle.
3. Sign it with Apple Hardened Runtime and App Sandbox entitlements.
4. Install it directly into `/Applications/LiveWallpaper.app`.

To launch the app immediately:

```bash
open /Applications/LiveWallpaper.app
```

---

## 🖥️ Installing the Companion Screen Saver

To install the matching aerial screen saver into macOS:

```bash
./build_screensaver.sh
```

This compiles and signs `LiveWallpaper.saver` directly into `~/Library/Screen Savers/LiveWallpaper.saver`. You can immediately preview and select it in **System Settings > Wallpaper / Screen Saver**.

---

## 🛡️ macOS Security & Gatekeeper Troubleshooting

When opening an ad-hoc signed app for the first time:

### Method A: Right-Click Open
1. Open Finder and go to `/Applications`.
2. **Right-click** (or `Control`-click) on **`LiveWallpaper.app`**.
3. Select **Open**.
4. In the dialog, click **Open** to confirm.

### Method B: Terminal Command (Clear Quarantine)
If macOS displays a warning that the developer cannot be verified:

```bash
xattr -cr /Applications/LiveWallpaper.app
open /Applications/LiveWallpaper.app
```

---

## 🗑️ Uninstallation

LiveWallpaper has no scattered background daemons or kernel extensions. To remove it:

```bash
# Terminate the running instance
killall LiveWallpaper 2>/dev/null || true

# Remove the application bundle
rm -rf /Applications/LiveWallpaper.app
rm -rf ~/Library/Screen\ Savers/LiveWallpaper.saver

# Optional: Remove user preferences, downloaded gallery loops, and cached posters
rm -rf ~/Library/Application\ Support/LiveWallpaper
defaults delete com.local.LiveWallpaper 2>/dev/null || true
```
