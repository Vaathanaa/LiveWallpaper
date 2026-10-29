# VideoBackdrop

<p align="center">
  <img src="Resources/AppIcon.png" alt="VideoBackdrop Logo" width="128" height="128" onerror="this.style.display='none'"/>
</p>

<p align="center">
  <strong>Ultra-efficient, buttery-smooth Live Video Wallpaper & Interactive Backdrop for macOS.</strong><br>
  Engineered natively in Swift and AppKit for Apple Silicon (M1, M2, M3, M4).
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2013%2B-blue?style=flat-square&logo=apple" alt="macOS 13+"/>
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-orange?style=flat-square" alt="Apple Silicon"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%2F%206.0-red?style=flat-square&logo=swift" alt="Swift"/>
  <img src="https://img.shields.io/badge/Dependencies-Zero%20(Pure%20Apple%20Frameworks)-green?style=flat-square" alt="Zero Dependencies"/>
  <img src="https://img.shields.io/badge/License-MIT-purple?style=flat-square" alt="MIT License"/>
</p>

---

## 🌟 Highlights & Key Features

- ⚡ **Zero-Copy Hardware VideoToolbox Decode**: Decodes H.264 & HEVC directly on Apple Silicon Media Engines. Sustains smooth 60fps, 120fps (ProMotion), and high-refresh external monitors (up to 200Hz+) with low CPU footprint.
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
  - Includes `VideoBackdrop.saver` to synchronize your active video wallpaper directly with macOS's native lock screen and aerial screen saver.

---

## 💻 System Requirements

| Requirement | Specification |
| :--- | :--- |
| **Operating System** | macOS 13.0 (Ventura), macOS 14.0 (Sonoma), macOS 15.0 (Sequoia), or later |
| **Architecture** | Apple Silicon (`arm64`): M1, M2, M3, M4 (Base, Pro, Max, Ultra) |
| **Toolchain** | Xcode 15+ / Swift 5.9+ |
| **Dependencies** | **None** (Built exclusively using AVFoundation, AppKit, SwiftUI, QuartzCore, WebKit, and IOKit) |

---

## 🚀 Quick Start & Installation

### Option 1: One-Line Build & Run (Terminal)

Clone this repository and run the automated build script:

```bash
git clone https://github.com/your-username/VideoBackdrop.git
cd VideoBackdrop
./build_app.sh
```

To install directly to `/Applications`:

```bash
cp -R VideoBackdrop.app /Applications/
open /Applications/VideoBackdrop.app
```

### Option 2: Install Companion Screen Saver

To build and install the native macOS screen saver bundle:

```bash
./build_screensaver.sh
```
The screen saver will be placed in `~/Library/Screen Savers/VideoBackdrop.saver` and will appear in **System Settings > Wallpaper / Screen Saver**.

---

## 🎮 Usage & Controls

Once launched, VideoBackdrop lives as a lightweight icon in your macOS menu bar (`play.desktopcomputer`):

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

VideoBackdrop includes a built-in `DistributedNotificationCenter` IPC interface. You can script playback from Terminal, Raycast, Alfred, or Shortcuts:

```bash
# Toggle Play/Pause
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.VideoBackdrop.togglePlayPause"), object: nil, deliverImmediately: true)'

# Pause
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.VideoBackdrop.pause"), object: nil, deliverImmediately: true)'

# Resume Play
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.VideoBackdrop.play"), object: nil, deliverImmediately: true)'

# Load a new video dynamically
swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.local.VideoBackdrop.loadVideo"), object: nil, userInfo: ["path": "/path/to/video.mp4"], deliverImmediately: true)'
```

---

## 🔬 Architecture & Performance

```
+-------------------------------------------------------------+
|                      macOS WindowServer                     |
|                                                             |
|  [Floating Windows / Apps] (Notes, Safari, iPhone Mirroring)|  Layer 0
|  ---------------------------------------------------------  |
|  [Desktop Icons & Widgets]                                  |  kCGDesktopIconWindowLevel
|  ---------------------------------------------------------  |
|  [BackdropWindow] (VideoBackdrop)                           |  kCGDesktopWindowLevel + 1
|    * Window: isOpaque = false, backgroundColor = .clear     |
|    * AVPlayerLayer: opacity = 0.999, isOpaque = false       |  (Metal GPU Compositor)
|    * Zero direct-scanout plane collisions                   |
|  ---------------------------------------------------------  |
|  [Root Desktop Picture]                                     |  kCGDesktopWindowLevel
+-------------------------------------------------------------+
```

### Performance Targets
- **CPU While Playing**: Under 3% on Apple Silicon M-series.
- **CPU While Paused**: **0.0% to 2.4%** (idling in Mach traps).
- **RAM**: Under 100 MB physical footprint.
- **Power**: Automatically drops power assertions when audio is muted.

---

## 🤝 Contributing

Contributions, bug reports, and pull requests are welcome!
1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
