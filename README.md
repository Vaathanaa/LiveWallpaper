# LiveWallpaper

<p align="center">
  <strong>Ultra-efficient, buttery-smooth Live Video Wallpaper & Interactive Backdrop for macOS.</strong><br>
  Engineered natively in Swift and AppKit for Apple Silicon (M1, M2, M3, M4).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="macOS 13+"/>
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange?style=flat-square" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%2F%206.0-red?style=flat-square&logo=swift" alt="Swift"/>
  <img src="https://img.shields.io/badge/Security-Hardened%20Runtime%20%26%20Sandbox%20Ready-success?style=flat-square&logo=apple" alt="Security"/>
  <img src="https://img.shields.io/badge/Privacy-Zero%20Telemetry%20%2F%20100%25%20Local-green?style=flat-square" alt="Privacy"/>
  <img src="https://img.shields.io/badge/License-MIT-purple?style=flat-square" alt="MIT License"/>
</p>

---

## 🌟 Highlights & Key Features

- ⚡ **Zero-Copy Hardware VideoToolbox Decode**: Decodes H.264 & HEVC directly on Apple Silicon Media Engines. Sustains smooth 60fps, 120fps (ProMotion), and high-refresh external monitors (up to 200Hz+) with minimal CPU footprint.
- ❄️ **Instant Freeze-Frame Pause**: Pausing never clears your screen or flashes black. It instantly captures and freezes the exact video frame as a crisp, static desktop picture.
- 📱 **Zero-Glitch iPhone Mirroring & PiP**: Engineered with non-exclusive GPU composition (`playerLayer.opacity = 0.999`, `isOpaque = false`), permanently preventing hardware video overlay contention with macOS Sequoia's iPhone Mirroring and Picture-in-Picture windows on external monitors.
- 🖥️ **Universal Multi-Display Architecture**:
  - **Same on All Displays**: Intelligently shares a single decoder pipeline across all monitors—halving unified memory bandwidth.
  - **Per-Display Mode**: Assign custom video backdrops independently to each monitor.
- 🔋 **Smart MagSafe & Battery Awareness**:
  - Automatically switches framerates based on power source (e.g., 120Hz on AC power, 60Hz/24Hz on battery).
  - Auto-pauses on Low Power Mode, thermal throttling, or when configured heavy apps/games are running.
- 🪐 **Interactive Web Shaders & Particles**:
  - WebKit-powered interactive GPU shaders (Cyberpunk Matrix, Deep Space Nebula, Particle Network, Clock Wave).
  - Native CoreAnimation procedural weather particles (Gentle Snow, Cherry Blossoms, Cinematic Rain, Floating Embers).
- 🖱️ **3D Mouse Parallax & Dynamic Depth**:
  - Smooth spring-mass-damper physics with menu bar and hot-corner safety cushions.
  - Automatically rests when mouse is idle, dropping timer and CADisplayLink ticks to 0.
- 🛡️ **Companion Screen Saver**:
  - Includes `LiveWallpaper.saver` to synchronize your active video wallpaper directly with macOS's native lock screen and aerial screen saver.

---

## 💻 System Requirements

| Requirement | Specification |
| :--- | :--- |
| **Operating System** | macOS 13.0 (Ventura), macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later |
| **Architecture** | Apple Silicon (`arm64`): M1, M2, M3, M4 (Base, Pro, Max, Ultra) |
| **Toolchain** | Xcode 15+ / Swift 5.9+ |
| **Security** | Built with Hardened Runtime and App Sandbox compatibility |
| **Privacy** | 100% local execution — zero network requests, zero telemetry ([Privacy Policy](PRIVACY.md)) |

---

## 🚀 Quick Start & Installation

Detailed instructions are available in [INSTALL.md](INSTALL.md).

### One-Line Build & Install to `/Applications`

```bash
git clone https://github.com/your-username/LiveWallpaper.git
cd LiveWallpaper
./build_app.sh
```

To launch immediately:

```bash
open /Applications/LiveWallpaper.app
```

### Install Companion Screen Saver

```bash
./build_screensaver.sh
```

---

## 🎮 Usage & Controls

Once launched, LiveWallpaper lives as a lightweight icon in your macOS menu bar (`play.desktopcomputer`):

- **Live Mini-Player Card**: Real-time thumbnail preview, timeline scrubber, and status badges.
- **Play / Pause (`⌘P`)**: Seamlessly freeze/resume playback.
- **Choose Video... (`⌘O`)**: Select any local `.mp4`, `.mov`, `.m4v` video.
- **Mute Audio (`⌘M`)**: Completely disables audio track rendering to release coreaudiod assertions.
- **Wallpaper Type**: Toggle between Video Files, Web Shaders, or Standalone Particles.
- **Weather Overlay**: Layer procedural snow, sakura, rain, embers, or stars on top of any video.
- **3D Mouse Parallax**: Toggle mouse-driven 3D depth and tilt.
- **Frame Rate**: Select 24, 30, 60, 120 fps or Smart Adaptive MagSafe profiling.
- **Displays**: Switch between "Same on All Displays" or assign individual wallpapers per monitor.
- **Launch at Login**: Integrates with `SMAppService` to boot silently on startup.

---

## ⌨️ CLI & Automation Commands

LiveWallpaper includes a built-in `DistributedNotificationCenter` IPC interface:

```bash
# Toggle Play/Pause
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.LiveWallpaper.togglePlayPause"), object: nil, deliverImmediately: true)'

# Pause
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.LiveWallpaper.pause"), object: nil, deliverImmediately: true)'

# Resume Play
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.LiveWallpaper.play"), object: nil, deliverImmediately: true)'

# Load a new video dynamically
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.LiveWallpaper.loadVideo"), object: nil, userInfo: ["path": "/path/to/video.mp4"], deliverImmediately: true)'
```

---

## 🔒 Security & Privacy Policy

LiveWallpaper is built with strict privacy compliance:
- **Zero Telemetry**: No tracking, analytics, or remote logging.
- **Sandboxed User File Access**: Reads only the files you pick via `NSOpenPanel`.
- **No Intrusive Permissions**: No Accessibility, no Screen Recording, no Camera, no Mic.

Read the full [Privacy Policy](PRIVACY.md).

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
