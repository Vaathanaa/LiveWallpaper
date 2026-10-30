# LiveWallpaper — Viral Launch & Search Algorithm Playbook

This playbook provides actionable steps, keyword optimization strategies, and ready-to-publish launch copy to get **LiveWallpaper** ranked #1 on Google, GitHub Search, and trending across Mac communities.

---

## 🎯 Step 1: Configure GitHub Repository Settings for Max Algorithmic Reach

Go to your repository on GitHub: `https://github.com/Vaathanaa/LiveWallpaper` -> Click the ⚙️ gear icon next to **About**:

### 1. Description (Keyword Dense)
> ⚡ Ultra-fast 120Hz ProMotion Live Wallpaper & Aerial Screen Saver Engine for macOS Apple Silicon (M1/M2/M3/M4). Zero-lag Metal shaders, video trimmer, battery adaptivity, and seamless lock screen sync.

### 2. Website URL
`https://github.com/Vaathanaa/LiveWallpaper`

### 3. Topics (Search Index Tags)
Add these exact 20 tags (GitHub limits to 20):
```
macos, live-wallpaper, wallpaper-engine, apple-silicon, metal, swift, screensaver, sequoia, sonoma, menubar-app, pro-motion, 120hz, mac-app, m1, m2, m3, m4, dynamic-wallpaper, video-wallpaper, xdr
```

---

## 🚀 Step 2: Publish GitHub Release v1.2.0 with Binary Installers

The installer suite is already built in `./dist/`:
- `LiveWallpaper-1.2.0.dmg` (1.7 MB)
- `LiveWallpaper-Installer-1.2.0.pkg` (1.5 MB)

To create the release on GitHub:
```bash
# Push tag to trigger automatic GitHub Actions build
git tag -a v1.2.0 -m "Release v1.2.0: 120Hz ProMotion Live Wallpaper & Screen Saver with DMG and PKG installers"
git push origin v1.2.0
```
Or upload the files from `./dist` to GitHub Releases manually under tag `v1.2.0`.

---

## 📢 Step 3: Launch on Reddit (r/macapps & r/mac)

Reddit drives massive inbound traffic that search engines heavily weight for ranking.

### Post Title for r/macapps & r/mac:
> **I built a 100% free, open-source 120Hz ProMotion Live Wallpaper & Screen Saver engine for Apple Silicon (<15MB RAM, 0% idle CPU)**

### Post Body:
```markdown
Hey everyone! 👋

I love live wallpapers on macOS, but existing solutions were either sluggish Windows ports running through emulation, bloated Electron wrappers that ate 25% CPU, or locked behind subscriptions.

So I built **LiveWallpaper** — a native Swift, AppKit, Metal 4, and AVFoundation live wallpaper engine engineered specifically for Apple Silicon (M1, M2, M3, M4):

### 🌟 Why it's different:
- **Locked 120Hz ProMotion**: Hardware-decoded via Apple Silicon Media Engines. Silky smooth on Liquid Retina XDR displays and 144Hz+ external monitors with ~0.5% CPU.
- **Flawless Screen Saver & Lock Screen Sync**: Automatically updates your Lock Screen poster and syncs active video loops directly to macOS's native 120Hz aerial screen saver engine.
- **Smart Battery Adaptivity**: Detects MagSafe unplugging and scales refresh rate (120fps -> 60fps/24fps) or auto-pauses on Low Power Mode.
- **Native Metal 4 Compute Shaders**: Procedural shaders (Deep Space Nebula, Matrix Rain, Northern Lights) running in under 15MB RAM!
- **Non-glitch iPhone Mirroring / PiP**: Composited with non-exclusive GPU scanout so it never collides with macOS Sequoia iPhone Mirroring.
- **100% Free & Open-Source**: Zero telemetry, zero ads, zero subscriptions.

### ⚡ Quick 1-Line Terminal Install:
```bash
curl -fsSL https://raw.githubusercontent.com/Vaathanaa/LiveWallpaper/main/install.sh | bash
```

Or grab the `.dmg` / `.pkg` installer from GitHub:
🔗 **GitHub**: https://github.com/Vaathanaa/LiveWallpaper

Would love to hear your feedback, feature ideas, and test results on different Mac models!
```

---

## ⚡ Step 4: Submit to Awesome-macOS and Open-Source Directories

These repositories have 35k+ stars. Being listed here permanently boosts domain authority on Google:

### 1. `serhii-londar/open-source-mac-os-apps` (37k+ stars)
Submit a Pull Request adding LiveWallpaper under the **Wallpaper / Screensaver** or **Customization** category:
```markdown
- [LiveWallpaper](https://github.com/Vaathanaa/LiveWallpaper) - 120Hz hardware-accelerated live video wallpaper and aerial screen saver engine for Apple Silicon. `[Free]` `[Swift]`
```

### 2. `iCHAIT/awesome-macOS` (27k+ stars)
Submit a Pull Request under **Desktop Utilities**:
```markdown
- [LiveWallpaper](https://github.com/Vaathanaa/LiveWallpaper) - Ultra-smooth 120Hz ProMotion live wallpaper and dynamic screen saver engine.
```

---

## 💡 Step 5: Post to Hacker News (Show HN)

### Title:
> `Show HN: LiveWallpaper – Native 120Hz live wallpaper & screen saver for Apple Silicon`

### Link:
`https://github.com/Vaathanaa/LiveWallpaper`

---

## 🌟 Step 6: Official Homebrew Cask Inclusion

Once the repository has a few stars, submit `Casks/livewallpaper.rb` to `Homebrew/homebrew-cask`:
```bash
brew create --cask https://github.com/Vaathanaa/LiveWallpaper/releases/download/v1.2.0/LiveWallpaper-1.2.0.dmg
```
Once merged into Homebrew, any Mac user in the world can install with:
```bash
brew install --cask livewallpaper
```
