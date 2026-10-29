# Security & User Privacy Policy

**LiveWallpaper** is engineered with strict adherence to Apple's macOS Security, Hardened Runtime, and User Privacy Guidelines.

---

## 🔒 1. Zero Data Collection & Zero Telemetry
- **100% Local Execution**: LiveWallpaper runs entirely offline on your Mac. It contains **no network analytics, no telemetry, no tracking SDKs, and no remote crash reporting**.
- **No Remote Servers**: The app never connects to any external servers. Your settings, chosen videos, and usage patterns remain exclusively on your local device.

---

## 🛡️ 2. User-Selected File Access (App Sandbox & Security-Scoped Bookmarks)
- **Zero Full-Disk Access**: LiveWallpaper **does not** require or request Full Disk Access (`kTCCServiceSystemPolicyAllFiles`).
- **User-Intent Access Only**: LiveWallpaper only accesses video files that you explicitly choose through the standard macOS file selection dialog (`NSOpenPanel`).
- **Security-Scoped Bookmarks**: Stored file access is maintained using Apple's Security-Scoped Bookmark architecture (`URL.bookmarkData(options: .withSecurityScope)`). Even across reboots, file access is limited strictly to the video files you selected.

---

## 🚫 3. No Invasive macOS Permissions
- **No Accessibility API (`AXUIElement`)**: LiveWallpaper does not monitor or inspect other applications via the macOS Accessibility layer.
- **No Keystroke Monitoring**: The app does not intercept, log, or observe user keystrokes.
- **No Screen Recording Permission**: The occlusion detection algorithm queries window bounding rectangles (`CGWindowListCopyWindowInfo`) at Layer 0 without reading, capturing, or recording the screen pixels of other windows.
- **No Camera / Microphone / Location / Contacts Access**: None of these hardware or personal data permissions are requested or used.

---

## ⚡ 4. Audio & Power Privacy
- **Muted by Default**: Audio playback is muted by default. When muted, the audio track is omitted from the decoding pipeline, ensuring `coreaudiod` never prevents your Mac from sleeping or claims unnecessary power assertions.

---

## 📜 5. Open Source Transparency
LiveWallpaper is completely open source under the **MIT License**. Every line of Swift code is auditable in this repository.
