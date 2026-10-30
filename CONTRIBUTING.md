# Contributing to LiveWallpaper

Thank you for your interest in contributing to **LiveWallpaper**! We welcome community contributions to build the fastest, most beautiful live wallpaper engine for macOS.

---

## 🛠️ Development Setup

### Prerequisites
- Mac with **Apple Silicon** (M1/M2/M3/M4)
- **macOS 13.0+** (Ventura, Sonoma, or Sequoia)
- **Xcode 15+** or Command Line Tools (`xcode-select --install`)

### Building Locally
```bash
git clone https://github.com/Vaathanaa/LiveWallpaper.git
cd LiveWallpaper

# Compile release binary and package app bundle
./build_app.sh

# Compile matching native screen saver bundle
./build_screensaver.sh

# Run the app
open /Applications/LiveWallpaper.app
```

---

## 📐 Architecture Highlights
- **Video Engine**: Zero-copy `AVSampleBufferDisplayLayer` and `AVPlayerLayer` tied directly to Apple Silicon Media Engine hardware decoders.
- **Metal 4 Shaders**: Custom Metal Shading Language compute kernels running in `<15MB` RAM with zero CPU usage.
- **ProMotion 120Hz**: DisplayLink synchronization locked to screen refresh rate with zero tearing.
- **Power Adaptivity**: MagSafe detection and automatic frame rate scaling (120fps -> 60fps/24fps) during battery operation.

---

## 🤝 Submitting Pull Requests
1. Fork the repo and create your branch from `main`.
2. Ensure Swift code compiles cleanly (`swift build`).
3. Commit with concise, descriptive commit messages adhering to Conventional Commits:
   - `feat: add ping-pong loop smoothing`
   - `fix: resolve multi-monitor scanout contention`
   - `perf: optimize Metal buffer allocation`
4. Open a Pull Request with a clear description of your changes and test results.
