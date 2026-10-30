# LiveWallpaper

<p align="center">
  <strong>The ultimate hardware-accelerated Live Video Wallpaper, Native Metal 4 Shader & Studio Hub for macOS.</strong><br>
  Engineered natively in Swift, AppKit, Metal, and AVFoundation for Apple Silicon (M1, M2, M3, M4).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="macOS 13+"/>
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange?style=flat-square" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/ProMotion-120Hz%20%2F%20200Hz%2B-purple?style=flat-square" alt="ProMotion 120Hz/200Hz"/>
  <img src="https://img.shields.io/badge/Memory-%3C15MB%20Metal%20%2F%20~100MB%204K-blueviolet?style=flat-square" alt="Memory"/>
  <img src="https://img.shields.io/badge/Security-Hardened%20Runtime%20%26%20Sandbox-success?style=flat-square&logo=apple" alt="Security"/>
  <img src="https://img.shields.io/badge/Privacy-Zero%20Telemetry%20%2F%20100%25%20Local-green?style=flat-square" alt="Privacy"/>
  <img src="https://img.shields.io/badge/License-MIT-purple?style=flat-square" alt="MIT License"/>
</p>

---

## 🌟 What Sets LiveWallpaper Apart

- ⚡ **Zero-Copy Hardware VideoToolbox Pipeline**: Direct hardware decode via Apple Silicon Media Engines. Sustains locked 60fps, 120fps (Liquid Retina XDR ProMotion), and up to 200Hz+ external gaming monitors with ~0.5% CPU.
- 🎨 **Apple Design Award (ADA) Studio & Video Trimmer**:
  - **Live Scrubber & Preview**: Scrub playheads with instant thumbnail rendering.
  - **Precision In / Out Trimmer**: Trim any video segment in real-time with custom loop boundaries.
  - **Looping Magic**: Seamless 0ms hardware looper, smooth Crossfade Dissolve overlap, and Ping-Pong reversal modes.
  - **Atmosphere & Color Grading**: Live Exposure EV, Contrast, Saturation, Cinematic Vignette, Frost Blur, and Dimming.
  - **Desktop Widget Readability Shield**: Soft ambient gradient shield making macOS Sonoma/Sequoia desktop widgets and top menu bar instantly readable on bright wallpapers.
  - **Dynamic Wallpaper Color Harmony**: Extracts live dominant palettes via CoreImage `CIAreaAverage` to dynamically tint app accents.
- 🚀 **Native Metal 4 Compute Shader Engine**:
  - Procedural Raymarched Shaders (*Deep Space Nebula*, *Cyberpunk Matrix Rain*, *Minimalist Liquid Fluid*, *Northern Aurora*) running directly on GPU compute cores.
  - Slashes unified memory footprint from 120MB down to **under 15MB with 0.1% CPU**.
- ❄️ **Instant Freeze-Frame Pause Guarantee**:
  - Pausing never shows a black screen or blank desktop. It instantly snapshots the active frame with zero visual flicker.
- 📱 **Zero-Glitch iPhone Mirroring & PiP**:
  - Non-exclusive GPU composition (`playerLayer.opacity = 0.999`) prevents hardware scanout plane contention with macOS Sequoia iPhone Mirroring and Picture-in-Picture windows.
- 🖥️ **Multi-Display Architecture**:
  - Shared decoder mode (halving memory bandwidth across monitors) or independent Per-Display wallpapers.
- 🔋 **Smart MagSafe & Battery Profiles**:
  - Dynamically scales framerate (120fps AC -> 60fps/24fps Battery -> Auto-pause on Low Power Mode / Heavy Games).
- 🖱️ **3D Mouse Parallax & Dynamic Depth**:
  - Velvety spring-mass-damper physics with menu-bar and hot-corner safety cushions.
  - Automatically sleeps CADisplayLink when the cursor is idle (0.0% idle CPU).
- 🔒 **Lock Screen & Screen Saver Synchronization**:
  - Automatically extracts 4K wallpaper posters for the macOS Lock Screen whenever a wallpaper is applied or paused.
  - Synchronizes active video wallpaper loops directly to macOS's native 120Hz Aerial Screen Saver engine.

---

## 💻 System Requirements

| Requirement | Specification |
| :--- | :--- |
| **Operating System** | macOS 13.0 (Ventura), macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later |
| **Architecture** | Apple Silicon (`arm64`): M1, M2, M3, M4 (Base, Pro, Max, Ultra) |
| **Toolchain** | Xcode 15+ / Swift 5.9+ |
| **Security** | Built with Hardened Runtime and App Sandbox compatibility |
| **Privacy** | 100% local execution — zero network telemetry ([Privacy Policy](PRIVACY.md)) |

---

## 🚀 Quick Start & Installation

Detailed instructions are available in [INSTALL.md](INSTALL.md).

### Option 1: Install via Homebrew Cask

```bash
brew install --cask ./Casks/livewallpaper.rb
```

### Option 2: Build & Install from Source

```bash
git clone https://github.com/Vaathanaa/LiveWallpaper.git
cd LiveWallpaper
./build_app.sh
```

To launch immediately:

```bash
open /Applications/LiveWallpaper.app
```

### Option 3: Install Companion Screen Saver

```bash
./build_screensaver.sh
```

---

## 🎮 Studio Hub & Controls

LiveWallpaper lives unobtrusively in your macOS menu bar (`play.desktopcomputer`):

- **Live Mini-Player Card**: Real-time thumbnail preview, timeline scrubber, and status badges.
- **Displays & Media Tab**: Video backdrop picker, live timeline playhead scrubber, multi-monitor configuration, Lock Screen & Screen Saver sync.
- **Studio & Loop Tab**: Video trimmer, playhead scrubber, crossfade looper, ping-pong reversal, speed, audio mute.
- **Atmosphere Tab**: Exposure, contrast, saturation, vignette, frost blur, widget readability cushion, dynamic color harmony.
- **Interactive & Shaders**: Native Metal 4 compute shaders, 3D mouse parallax, weather particle overlays.
- **Playlist & Schedule**: Multi-video rotation queue, automatic day and night mode switching.
- **Performance & Battery**: Smart MagSafe adaptive framerate, auto-pause during games or heavy apps, launch at login.

---

## ⌨️ CLI & Automation Commands

Control LiveWallpaper via macOS `DistributedNotificationCenter` from Terminal, Raycast, or Alfred:

```bash
# Toggle Play/Pause
osascript -e 'tell application "LiveWallpaper" to activate'
# Or via distributed notification:
python3 -c "from Foundation import NSDistributedNotificationCenter; NSDistributedNotificationCenter.defaultCenter().postNotificationName_object_('com.local.LiveWallpaper.togglePlayback', None)"
```

---

## 📜 Privacy & Security

LiveWallpaper is built with a strict **Privacy-First, Zero-Telemetry** architecture:
- 100% Local Processing — all video decoding and shader computation happens on-device.
- Hardened Runtime enabled with strict user-selected read-only sandbox entitlements.
- Zero analytics, zero logging, zero background tracking. Read the full [PRIVACY.md](PRIVACY.md).

---

## 📄 License

LiveWallpaper is open source software released under the [MIT License](LICENSE).
