# LiveWallpaper Installation & Distribution Guide

Choose the installation method that fits your workflow best. All methods install natively into `/Applications` on Apple Silicon Macs (**M1, M2, M3, M4**).

---

## 🚀 Installation Options

### Option 1: 1-Line Terminal Quick Install (Recommended)
Open **Terminal** and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/Vaathanaa/LiveWallpaper/main/install.sh | bash
```

**What this does automatically:**
- Detects your Apple Silicon architecture.
- Installs `LiveWallpaper.app` directly into `/Applications`.
- Installs `LiveWallpaper.saver` into your screen savers directory.
- Clears Gatekeeper quarantine attributes (`xattr -cr`).
- Registers and launches the app into your menu bar.

---

### Option 2: Guided macOS Installer Wizard (`.pkg`)
For enterprise users or those who prefer a traditional macOS installer wizard:

1. Download **`LiveWallpaper-Installer-1.2.0.pkg`** from [Latest Releases](https://github.com/Vaathanaa/LiveWallpaper/releases/latest).
2. Double-click the `.pkg` file.
3. Follow the guided installation wizard.
4. Launch `LiveWallpaper` from `/Applications` or Spotlight.

---

### Option 3: Drag-and-Drop Disk Image (`.dmg`)
1. Download **`LiveWallpaper-1.2.0.dmg`** from [Latest Releases](https://github.com/Vaathanaa/LiveWallpaper/releases/latest).
2. Double-click to mount the `.dmg`.
3. Drag **`LiveWallpaper.app`** to the **Applications** folder shortcut.
4. *(Optional)* Drag **`LiveWallpaper.saver`** to **Screen Savers**.

---

### Option 4: Homebrew Cask

```bash
# Direct Cask installation from repo:
brew install --cask ./Casks/livewallpaper.rb
```

---

### Option 5: Build from Source

```bash
git clone https://github.com/Vaathanaa/LiveWallpaper.git
cd LiveWallpaper

# Build app and screen saver
./build_app.sh
./build_screensaver.sh

# Launch immediately
open /Applications/LiveWallpaper.app
```

To create your own standalone `.dmg` and `.pkg` installers:

```bash
./create_installer.sh
```
The output installers will be generated inside the `./dist` folder.

---

## 🛡️ macOS Security & Gatekeeper Note

Because LiveWallpaper is distributed independently as an open-source binary:

If macOS displays a notice that the developer cannot be verified upon first launch:
1. **Right-click** (or `Control`-click) on `/Applications/LiveWallpaper.app`.
2. Select **Open**, then click **Open** in the dialog.
3. Or run this one-line command in Terminal:
   ```bash
   xattr -cr /Applications/LiveWallpaper.app
   ```

---

## 🗑️ Uninstallation

LiveWallpaper has no background daemons or kernel extensions:

```bash
killall LiveWallpaper 2>/dev/null || true
rm -rf /Applications/LiveWallpaper.app
rm -rf ~/Library/Screen\ Savers/LiveWallpaper.saver
rm -rf ~/Library/Application\ Support/LiveWallpaper
```
