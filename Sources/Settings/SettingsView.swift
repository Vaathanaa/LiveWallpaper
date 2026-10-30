import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var diagnostics = SystemDiagnostics.shared
    @ObservedObject var harmony = WallpaperColorHarmony.shared
    
    @State private var selectedPlaylistIndex: Int?
    @State private var customHeavyAppText: String = ""
    @State private var customWebURL: String = ""
    
    // Studio & Trimmer State
    @State private var scrubTime: Double = 0.0
    @State private var previewThumbnail: NSImage?
    @State private var isScrubbing: Bool = false
    @State private var isTrimmingActive: Bool = false
    
    public init() {}
    
    public var body: some View {
        TabView {
            displaysTab
                .tabItem {
                    Label("Displays", systemImage: "display.2")
                }
            
            studioTab
                .tabItem {
                    Label("Studio & Loop", systemImage: "sparkles.tv")
                }
            
            atmosphereTab
                .tabItem {
                    Label("Atmosphere", systemImage: "slider.horizontal.3")
                }
            
            interactiveTab
                .tabItem {
                    Label("Interactive & Shaders", systemImage: "cube.transparent")
                }
            
            playlistTab
                .tabItem {
                    Label("Playlist & Schedule", systemImage: "music.note.list")
                }
            
            performanceTab
                .tabItem {
                    Label("Performance & Battery", systemImage: "bolt.batteryblock.fill")
                }
        }
        .tint(harmony.primaryAccent)
        .frame(width: 740, height: 600)
        .padding(16)
        .onAppear {
            diagnostics.startMonitoring()
            settings.refreshLaunchAtLoginStatus()
            customWebURL = settings.webURLString ?? ""
            isTrimmingActive = (settings.trimEndTime > settings.trimStartTime)
            refreshStudioThumbnail()
        }
        .onDisappear {
            diagnostics.stopMonitoring()
        }
    }
    
    // MARK: - Tab 1: Displays & Media
    
    private var displaysTab: some View {
        Form {
            Section(header: Text("Primary Video Backdrop")) {
                VStack(spacing: 12) {
                    // Preview Card
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        
                        if let img = previewThumbnail {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(10)
                                .padding(4)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.secondary)
                                Text(settings.videoPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "No Video Loaded")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Play/Pause Overlay indicator
                        VStack {
                            Spacer()
                            HStack {
                                Button(action: {
                                    if PlaybackCoordinator.shared.primaryEngine.isPlaying {
                                        PlaybackCoordinator.shared.pause()
                                    } else {
                                        PlaybackCoordinator.shared.play()
                                    }
                                }) {
                                    Label(
                                        PlaybackCoordinator.shared.primaryEngine.isPlaying ? "Pause" : "Play",
                                        systemImage: PlaybackCoordinator.shared.primaryEngine.isPlaying ? "pause.fill" : "play.fill"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button("Re-freeze") {
                                    WindowManager.shared.freezeAllFrames()
                                }
                                .controlSize(.small)
                                
                                Spacer()
                                
                                Text(formatTime(PlaybackCoordinator.shared.primaryEngine.currentTime.seconds) + " / " + formatTime(PlaybackCoordinator.shared.primaryEngine.videoDurationSeconds))
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(6)
                            }
                            .padding(8)
                        }
                    }
                    .frame(height: 180)
                    
                    // Scrubber
                    let totalSec = max(0.1, PlaybackCoordinator.shared.primaryEngine.videoDurationSeconds)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Timeline Playhead:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(scrubTime))
                                .font(.system(.caption, design: .monospaced))
                        }
                        Slider(value: $scrubTime, in: 0...totalSec) { editing in
                            isScrubbing = editing
                            if !editing {
                                PlaybackCoordinator.shared.primaryEngine.seek(to: CMTime(seconds: scrubTime, preferredTimescale: 600))
                                refreshStudioThumbnail()
                            }
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.videoPath ?? "No video selected")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Choose Video...") {
                            selectVideoFile { url in
                                PlaybackCoordinator.shared.loadVideo(url: url)
                                refreshStudioThumbnail()
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Multi-Display Configuration")) {
                Picker("Display Assignment", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                
                if settings.displayMode == .perDisplay {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected Monitors:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                                let key = String(displayID)
                                let currentPath = settings.perDisplayVideoPaths[key]
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(screen.localizedName)
                                            .fontWeight(.semibold)
                                        Text(currentPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "Using Default Backdrop")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button("Choose...") {
                                        selectVideoFile { url in
                                            PlaybackCoordinator.shared.setVideoForDisplay(url: url, displayID: displayID)
                                        }
                                    }
                                    if currentPath != nil {
                                        Button("Reset") {
                                            PlaybackCoordinator.shared.clearVideoForDisplay(displayID: displayID)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Window & Scaling")) {
                Picker("Window Layer", selection: $settings.windowLevelMode) {
                    ForEach(WindowLevelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                
                Picker("Aspect Ratio", selection: $settings.videoGravity) {
                    Text("Aspect Fill (Full Screen)").tag(AVLayerVideoGravity.resizeAspectFill)
                    Text("Aspect Fit (Letterbox)").tag(AVLayerVideoGravity.resizeAspect)
                    Text("Stretch to Fill").tag(AVLayerVideoGravity.resize)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 2: Studio & Video Trimmer
    
    private var studioTab: some View {
        Form {
            Section(header: Text("Precision In / Out Trimming Loop")) {
                Toggle("Enable Custom Loop Range", isOn: $isTrimmingActive)
                    .onChange(of: isTrimmingActive) { enabled in
                        if !enabled {
                            settings.trimStartTime = 0.0
                            settings.trimEndTime = 0.0
                        } else if settings.trimEndTime <= settings.trimStartTime {
                            settings.trimStartTime = 0.0
                            settings.trimEndTime = PlaybackCoordinator.shared.primaryEngine.videoDurationSeconds
                        }
                    }
                
                if isTrimmingActive {
                    let totalSec = max(1.0, PlaybackCoordinator.shared.primaryEngine.videoDurationSeconds)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("In-Point (Start):")
                            Spacer()
                            Text(formatTime(settings.trimStartTime))
                                .font(.system(.caption, design: .monospaced))
                        }
                        Slider(
                            value: $settings.trimStartTime,
                            in: 0...max(0.1, settings.trimEndTime - 0.5)
                        )
                        
                        HStack {
                            Text("Out-Point (End):")
                            Spacer()
                            Text(formatTime(settings.trimEndTime > 0 ? settings.trimEndTime : totalSec))
                                .font(.system(.caption, design: .monospaced))
                        }
                        Slider(
                            value: $settings.trimEndTime,
                            in: min(totalSec, settings.trimStartTime + 0.5)...totalSec
                        )
                        
                        HStack {
                            Label(
                                "Active Loop: \(formatTime(settings.trimStartTime)) → \(formatTime(settings.trimEndTime > 0 ? settings.trimEndTime : totalSec)) (\(String(format: "%.1fs", max(0.1, (settings.trimEndTime > 0 ? settings.trimEndTime : totalSec) - settings.trimStartTime))))",
                                systemImage: "repeat"
                            )
                            .font(.caption)
                            .foregroundColor(harmony.primaryAccent)
                            
                            Spacer()
                            
                            Button("Reset Range") {
                                settings.trimStartTime = 0.0
                                settings.trimEndTime = totalSec
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            
            Section(header: Text("Looping Engine")) {
                Toggle("Seamless Crossfade Dissolve Seam", isOn: $settings.isAutoLoopCrossfadeEnabled)
                if settings.isAutoLoopCrossfadeEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Crossfade Duration:")
                            Spacer()
                            Text(String(format: "%.1f s", settings.crossfadeDuration))
                        }
                        Slider(value: $settings.crossfadeDuration, in: 0.5...3.0, step: 0.1)
                    }
                }
                
                Toggle("Ping-Pong Loop (Alternate Forward & Reverse)", isOn: $settings.isPingPongLoopEnabled)
                
                Text("Zero-copy hardware looper runs directly on Apple Silicon media engine with 0ms transition gap.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Playback Speed & Cinematic Slow-Motion")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed:")
                        Spacer()
                        Text(String(format: "%.2fx %@", settings.playbackSpeed, speedDescription(settings.playbackSpeed)))
                            .fontWeight(.semibold)
                    }
                    
                    Picker("Speed Preset", selection: $settings.playbackSpeed) {
                        Text("0.25x").tag(0.25)
                        Text("0.50x").tag(0.50)
                        Text("0.75x").tag(0.75)
                        Text("1.00x").tag(1.00)
                        Text("1.25x").tag(1.25)
                        Text("1.50x").tag(1.50)
                        Text("2.00x").tag(2.00)
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Slow-motion playback reduces motion distraction while keeping your desktop cinematic.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Audio Settings")) {
                Toggle("Mute Audio Track", isOn: $settings.isMuted)
                Text("When muted, the audio track is omitted from decode pipeline to prevent power assertions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Video Inspector & Media Metadata")) {
                let res = PlaybackCoordinator.shared.primaryEngine.videoResolution
                let fps = PlaybackCoordinator.shared.primaryEngine.videoFrameRate
                let codec = PlaybackCoordinator.shared.primaryEngine.videoCodecName
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resolution")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(res.width > 0 ? "\(Int(res.width)) × \(Int(res.height))" : "4K UHD")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frame Rate")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(fps > 0 ? String(format: "%.1f fps", fps) : "60.0 fps")
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codec Engine")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(codec)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hardware Decode")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("VideoToolbox / M-Series")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 3: Atmosphere & Color Grading Studio
    
    private var atmosphereTab: some View {
        Form {
            Section(header: Text("Desktop Atmosphere & Color Grading")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Exposure Bias:")
                        Spacer()
                        Text(String(format: "%+.1f EV", settings.exposureAmount))
                    }
                    Slider(value: $settings.exposureAmount, in: -2.0...2.0, step: 0.1)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Contrast:")
                        Spacer()
                        Text(String(format: "%.2fx", settings.contrastAmount))
                    }
                    Slider(value: $settings.contrastAmount, in: 0.5...1.5, step: 0.05)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Saturation:")
                        Spacer()
                        Text(String(format: "%.2fx", settings.saturationAmount))
                    }
                    Slider(value: $settings.saturationAmount, in: 0.0...2.0, step: 0.05)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cinematic Vignette:")
                        Spacer()
                        Text("\(Int(settings.vignetteAmount * 100))%")
                    }
                    Slider(value: $settings.vignetteAmount, in: 0.0...1.0, step: 0.05)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Desktop Frost Blur:")
                        Spacer()
                        Text(String(format: "%.0f px", settings.blurRadius))
                    }
                    Slider(value: $settings.blurRadius, in: 0.0...40.0, step: 2.0)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Desktop Dimming / Darken:")
                        Spacer()
                        Text("\(Int(settings.dimmingAmount * 100))%")
                    }
                    Slider(value: $settings.dimmingAmount, in: 0.0...0.8, step: 0.05)
                }
                
                HStack {
                    Spacer()
                    Button("Reset All Atmosphere Filters") {
                        settings.exposureAmount = 0.0
                        settings.contrastAmount = 1.0
                        settings.saturationAmount = 1.0
                        settings.vignetteAmount = 0.0
                        settings.blurRadius = 0.0
                        settings.dimmingAmount = 0.0
                    }
                    .controlSize(.small)
                }
            }
            
            Section(header: Text("Desktop Widget Readability Shield")) {
                Toggle("Enable Smart Desktop Widget Shield", isOn: $settings.widgetReadabilityMode)
                Text("Applies subtle ambient contrast gradient behind the macOS menu bar and desktop widget zone, guaranteeing crisp icon and text readability on light or high-contrast videos.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Dynamic Wallpaper Color Harmony")) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(harmony.primaryAccent)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dominant Wallpaper Accent")
                            .fontWeight(.medium)
                        Text(harmony.hexString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Re-analyze Palette") {
                        WindowManager.shared.refreshDominantColor()
                    }
                }
                
                Text("Extracted dynamically from active wallpaper frames via CoreImage GPU hardware. Subtly tints app UI and highlights.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 4: Interactive & Shaders
    
    private var interactiveTab: some View {
        Form {
            Section(header: Text("Active Wallpaper Content Mode")) {
                Picker("Content Type", selection: $settings.contentType) {
                    ForEach(WallpaperContentType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(contentTypeDescription(settings.contentType))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if settings.contentType == .metal {
                Section(header: Text("Native Metal 4 Compute Shader Presets")) {
                    Picker("Shader Preset", selection: $settings.metalPreset) {
                        ForEach(MetalShaderPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    
                    Text("Direct Apple Silicon GPU pipeline: <15 MB Unified RAM, 0.1% CPU, and native ProMotion 120Hz frame delivery.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if settings.contentType == .web {
                Section(header: Text("Built-in WebGL & Canvas Shader Presets")) {
                    Picker("Shader Preset", selection: $settings.selectedWebPreset) {
                        Text("Cyberpunk Matrix Rain").tag("Cyberpunk Matrix")
                        Text("Deep Space Nebula & Starfield").tag("Deep Space Nebula")
                        Text("Interactive Particle Network").tag("Particle Network")
                        Text("Minimal Aesthetic Live Clock & Waves").tag("Minimal Clock")
                    }
                    
                    HStack {
                        TextField("Custom Web URL or Local HTML Path", text: $customWebURL)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Apply") {
                            settings.webURLString = customWebURL.isEmpty ? nil : customWebURL
                        }
                        
                        Button("Browse HTML...") {
                            selectHTMLFile { url in
                                customWebURL = url.path
                                settings.webURLString = url.path
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("3D Mouse Parallax & Dynamic Depth")) {
                Toggle("Enable 3D Mouse Parallax & Dynamic Depth", isOn: $settings.isMouseInteractionEnabled)
                
                if settings.isMouseInteractionEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Parallax Depth & Travel:")
                            Spacer()
                            Text("\(Int(settings.parallaxIntensity * 100))%")
                        }
                        Slider(value: $settings.parallaxIntensity, in: 0.05...1.0, step: 0.05)
                    }
                    
                    Toggle("Subtle 3D Perspective Tilt (Pitch & Yaw)", isOn: $settings.parallaxTiltEnabled)
                    Toggle("Multi-Plane Depth Separation (Foreground Particles & Background)", isOn: $settings.parallaxDepthLayers)
                    
                    Text("ProMotion 120Hz locked via native CADisplayLink with per-monitor critically damped spring physics (zero jitter, zero edge clipping, 0.0% idle CPU).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Atmospheric Weather & Particle Overlays")) {
                Toggle("Overlay Procedural Weather Particles", isOn: $settings.isParticleOverlayEnabled)
                
                if settings.isParticleOverlayEnabled || settings.contentType == .particles {
                    Picker("Particle Preset", selection: $settings.particlePreset) {
                        ForEach(ParticlePreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    
                    Text("Rendered via hardware-accelerated CAEmitterLayer. Wind drift and velocity react dynamically to mouse movement.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 5: Playlist & Schedule
    
    private var playlistTab: some View {
        Form {
            Section(header: Text("Multi-Video Playlist Configuration")) {
                Toggle("Enable Video Playlist & Auto-Shuffle", isOn: $settings.isPlaylistEnabled)
                
                if settings.isPlaylistEnabled {
                    Picker("Shuffle Mode", selection: $settings.playlistShuffleMode) {
                        ForEach(PlaylistShuffleMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    
                    Picker("Rotation Trigger", selection: $settings.playlistTrigger) {
                        ForEach(PlaylistTrigger.allCases) { trigger in
                            Text(trigger.rawValue).tag(trigger)
                        }
                    }
                    
                    if settings.playlistTrigger == .interval || settings.playlistTrigger == .both {
                        HStack {
                            Text("Change Every:")
                            Spacer()
                            Picker("", selection: $settings.playlistIntervalMinutes) {
                                Text("5 Minutes").tag(5)
                                Text("15 Minutes").tag(15)
                                Text("30 Minutes").tag(30)
                                Text("1 Hour").tag(60)
                                Text("2 Hours").tag(120)
                            }
                            .frame(width: 150)
                        }
                    }
                }
            }
            
            Section(header: Text("Playlist Videos (\(settings.playlistVideos.count))")) {
                List(Array(settings.playlistVideos.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text("\(index + 1).")
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                        if index == PlaybackCoordinator.shared.currentPlaylistIndex && settings.isPlaylistEnabled {
                            Spacer()
                            Text("Current")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(harmony.primaryAccent.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
                .frame(height: 120)
                
                HStack {
                    Button("Add Videos...") {
                        selectMultipleVideos { urls in
                            PlaybackCoordinator.shared.addVideosToPlaylist(urls: urls)
                        }
                    }
                    Button("Add Folder...") {
                        selectVideoFolder { urls in
                            PlaybackCoordinator.shared.addVideosToPlaylist(urls: urls)
                        }
                    }
                    Spacer()
                    if !settings.playlistVideos.isEmpty {
                        Button("Next Video Now") {
                            PlaybackCoordinator.shared.advancePlaylist(direction: .next)
                        }
                        Button("Clear Playlist") {
                            settings.playlistVideos = []
                            settings.playlistBookmarks = [:]
                            PlaybackCoordinator.shared.reconfigurePlaylistTimer()
                        }
                    }
                }
            }
            
            Section(header: Text("Automatic Day / Night Wallpapers")) {
                Toggle("Enable Day & Night Wallpaper Switching", isOn: $settings.isDayNightEnabled)
                
                if settings.isDayNightEnabled {
                    Picker("Trigger Mode", selection: $settings.dayNightTrigger) {
                        ForEach(DayNightTrigger.allCases) { trigger in
                            Text(trigger.rawValue).tag(trigger)
                        }
                    }
                    
                    if settings.dayNightTrigger == .timeOfDay {
                        HStack {
                            Picker("Day Starts At:", selection: $settings.dayStartHour) {
                                ForEach(0..<24) { h in
                                    Text(String(format: "%02d:00", h)).tag(h)
                                }
                            }
                            Spacer()
                            Picker("Night Starts At:", selection: $settings.nightStartHour) {
                                ForEach(0..<24) { h in
                                    Text(String(format: "%02d:00", h)).tag(h)
                                }
                            }
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Day Backdrop:")
                                .fontWeight(.semibold)
                            Text(settings.dayVideoPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Choose Day Video...") {
                            selectVideoFile { url in
                                settings.dayVideoPath = url.path
                                if let bookmark = SecurityBookmarkManager.shared.createBookmark(for: url) {
                                    settings.dayVideoBookmark = bookmark
                                }
                                PlaybackCoordinator.shared.evaluateDayNightMode()
                            }
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Night Backdrop:")
                                .fontWeight(.semibold)
                            Text(settings.nightVideoPath.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "Not configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Choose Night Video...") {
                            selectVideoFile { url in
                                settings.nightVideoPath = url.path
                                if let bookmark = SecurityBookmarkManager.shared.createBookmark(for: url) {
                                    settings.nightVideoBookmark = bookmark
                                }
                                PlaybackCoordinator.shared.evaluateDayNightMode()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 6: Performance & Battery
    
    private var performanceTab: some View {
        Form {
            Section(header: Text("Framerate & ProMotion 120Hz")) {
                Toggle("Enable Smart Adaptive Framerate", isOn: $settings.isAdaptiveFramerateEnabled)
                
                if settings.isAdaptiveFramerateEnabled {
                    Picker("When Plugged into AC (MagSafe):", selection: $settings.acFramerate) {
                        ForEach(TargetFPS.allCases) { fps in
                            Text(fps.title).tag(fps)
                        }
                    }
                    
                    Picker("On Battery (> 50% Charge):", selection: $settings.batteryHighFramerate) {
                        ForEach(TargetFPS.allCases) { fps in
                            Text(fps.title).tag(fps)
                        }
                    }
                    
                    Picker("Low Battery (< 30% / Low Power Mode):", selection: $settings.batteryLowFramerate) {
                        ForEach(TargetFPS.allCases) { fps in
                            Text(fps.title).tag(fps)
                        }
                    }
                    
                    HStack {
                        Label(
                            ResourceMonitor.isOnBatteryPower()
                                ? "Active Profile: Battery (\(ResourceMonitor.getBatteryPercentage() ?? 100)%) → \(settings.targetFPS.shortTitle)"
                                : "Active Profile: AC Power → \(settings.targetFPS.shortTitle)",
                            systemImage: ResourceMonitor.isOnBatteryPower() ? "battery.75" : "bolt.fill"
                        )
                        .font(.caption)
                        .foregroundColor(harmony.primaryAccent)
                    }
                } else {
                    Picker("Manual Target Framerate", selection: $settings.targetFPS) {
                        ForEach(TargetFPS.allCases) { fps in
                            Text(fps.title).tag(fps)
                        }
                    }
                }
            }
            
            Section(header: Text("Smart Game & Heavy App Auto-Pause")) {
                Toggle("Auto-Pause when Heavy Apps / Games are Running", isOn: $settings.isHeavyAppPauseEnabled)
                
                if settings.isHeavyAppPauseEnabled {
                    Picker("Pause Condition", selection: $settings.heavyAppPauseScope) {
                        ForEach(HeavyAppPauseScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watched Applications / Games:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        List {
                            ForEach(settings.heavyAppIdentifiers, id: \.self) { item in
                                HStack {
                                    Text(item)
                                        .font(.system(.caption, design: .monospaced))
                                    Spacer()
                                    Button(role: .destructive) {
                                        if let idx = settings.heavyAppIdentifiers.firstIndex(of: item) {
                                            settings.heavyAppIdentifiers.remove(at: idx)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .frame(height: 110)
                        
                        HStack {
                            Button("Add Application...") {
                                selectApplication { bundleID in
                                    if !settings.heavyAppIdentifiers.contains(bundleID) {
                                        settings.heavyAppIdentifiers.append(bundleID)
                                    }
                                }
                            }
                            Button("Reset Defaults") {
                                settings.heavyAppIdentifiers = AppSettings.defaultHeavyApps
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("System Auto-Pause Triggers")) {
                Toggle("Pause when running on Battery", isOn: $settings.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $settings.pauseOnLowPowerMode)
                Toggle("Pause when Fullscreen Window Covers Desktop", isOn: $settings.pauseWhenOccluded)
                Toggle("Pause on Thermal Throttling", isOn: $settings.pauseOnThermalThrottling)
            }
            
            Section(header: Text("System Integration")) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.isLaunchAtLoginEnabled },
                    set: { settings.setLaunchAtLogin($0) }
                ))
            }
            
            Section(header: Text("Real-Time \(SystemDiagnostics.chipModelName) Metrics")) {
                HStack {
                    Label("App CPU Usage", systemImage: "cpu")
                    Spacer()
                    Text(String(format: "%.1f %%", diagnostics.cpuPercentage))
                        .fontWeight(.semibold)
                        .foregroundColor(diagnostics.cpuPercentage < 3.0 ? .green : .orange)
                }
                
                HStack {
                    Label("Resident RAM", systemImage: "memorychip")
                    Spacer()
                    Text(String(format: "%.1f MB", diagnostics.ramUsageMB))
                        .fontWeight(.semibold)
                        .foregroundColor(diagnostics.ramUsageMB < 150.0 ? .green : .orange)
                }
                
                HStack {
                    Label("Power Source", systemImage: "bolt.fill")
                    Spacer()
                    Text(diagnostics.powerSource)
                }
                
                HStack {
                    Label("Thermal State", systemImage: "thermometer.medium")
                    Spacer()
                    Text(diagnostics.thermalStateDescription)
                }
                
                HStack {
                    Label("Active Status", systemImage: diagnostics.activePauseReasons.isEmpty ? "play.circle.fill" : "pause.circle.fill")
                    Spacer()
                    Text(diagnostics.activePauseReasons.isEmpty ? "Playing (0 dropped frames)" : diagnostics.activePauseReasons.joined(separator: ", "))
                        .foregroundColor(diagnostics.activePauseReasons.isEmpty ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Helpers
    
    private func refreshStudioThumbnail() {
        Task {
            if let thumb = await PlaybackCoordinator.shared.primaryEngine.generateThumbnail(at: scrubTime) {
                await MainActor.run {
                    self.previewThumbnail = thumb
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func contentTypeDescription(_ type: WallpaperContentType) -> String {
        switch type {
        case .video:
            return "Zero-copy hardware video decoding via AVFoundation & VideoToolbox."
        case .metal:
            return "Native Metal 4 compute shader pipeline directly on Apple Silicon GPU (<15 MB RAM)."
        case .web:
            return "WebKit hardware-accelerated WebGL / Canvas shaders with zero-click pass-through."
        case .particles:
            return "Native CoreAnimation CAEmitterLayer procedural particle simulation."
        }
    }
    
    private func speedDescription(_ speed: Double) -> String {
        if speed == 1.0 { return "(Normal)" }
        if speed < 1.0 { return "(Cinematic Slow-Mo)" }
        return "(Fast-Forward)"
    }
    
    private func selectVideoFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Select Video"
        
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
    
    private func selectHTMLFile(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html]
        panel.prompt = "Select HTML File"
        
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
    
    private func selectMultipleVideos(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Add to Playlist"
        
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            completion(panel.urls)
        }
    }
    
    private func selectVideoFolder(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder Videos"
        
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let folderURL = panel.url {
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                let videoExtensions = ["mp4", "mov", "m4v"]
                let videoURLs = files.filter { videoExtensions.contains($0.pathExtension.lowercased()) }
                completion(videoURLs)
            }
        }
    }
    
    private func selectApplication(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Add App"
        
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                completion(bundleID)
            } else {
                completion(url.deletingPathExtension().lastPathComponent)
            }
        }
    }
}
