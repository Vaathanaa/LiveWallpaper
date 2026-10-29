import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var diagnostics = SystemDiagnostics.shared
    
    @State private var selectedPlaylistIndex: Int?
    @State private var customHeavyAppText: String = ""
    @State private var customWebURL: String = ""
    
    public init() {}
    
    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("Displays", systemImage: "display.2")
                }
            
            interactiveTab
                .tabItem {
                    Label("Interactive & Shaders", systemImage: "sparkles.rectangle.stack")
                }
            
            dayNightTab
                .tabItem {
                    Label("Day & Night", systemImage: "sun.and.horizon.fill")
                }
            
            playlistTab
                .tabItem {
                    Label("Playlist", systemImage: "music.note.list")
                }
            
            playbackTab
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }
            
            powerTab
                .tabItem {
                    Label("Smart Pause", systemImage: "gamecontroller.fill")
                }
            
            diagnosticsTab
                .tabItem {
                    Label("Diagnostics", systemImage: "chart.xyaxis.line")
                }
        }
        .frame(width: 680, height: 560)
        .padding(16)
        .onAppear {
            diagnostics.startMonitoring()
            settings.refreshLaunchAtLoginStatus()
            customWebURL = settings.webURLString ?? ""
        }
        .onDisappear {
            diagnostics.stopMonitoring()
        }
    }
    
    // MARK: - Tab 1: Video & Displays
    
    private var generalTab: some View {
        Form {
            Section(header: Text("Primary Video Backdrop")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.videoPath ?? "No video selected")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(.body, design: .monospaced))
                        
                        Text("Default live wallpaper stream used across displays.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Choose Video...") {
                        selectVideoFile { url in
                            PlaybackCoordinator.shared.loadVideo(url: url)
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
            
            Section(header: Text("Desktop Readability & Dimming")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Dimming / Darken:")
                        Spacer()
                        Text("\(Int(settings.dimmingAmount * 100))%")
                    }
                    Slider(value: $settings.dimmingAmount, in: 0.0...0.8, step: 0.05)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Desktop Blur (Frost):")
                        Spacer()
                        Text(String(format: "%.0f px", settings.blurRadius))
                    }
                    Slider(value: $settings.blurRadius, in: 0.0...40.0, step: 2.0)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 2: Interactive Content Types & Shaders
    
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
                    
                    Text("WebKit transparent backing store with 0.0% CPU when desktop is occluded or in sleep.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    
    // MARK: - Tab 3: Day & Night Mode
    
    private var dayNightTab: some View {
        Form {
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
                    
                    // Day Video
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
                    
                    // Night Video
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
    
    // MARK: - Tab 4: Feature 2 - Playlist & Shuffle
    
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
                                .background(Color.accentColor.opacity(0.2))
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
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 5: Feature 4 - Playback & Speed
    
    private var playbackTab: some View {
        Form {
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
            
            Section(header: Text("Smart Battery Profiles & MagSafe Adaptivity")) {
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
                        .foregroundColor(.accentColor)
                    }
                } else {
                    Picker("Manual Target Framerate", selection: $settings.targetFPS) {
                        ForEach(TargetFPS.allCases) { fps in
                            Text(fps.title).tag(fps)
                        }
                    }
                }
                
                Text("Dynamically adjusts decode framerate to maximize Liquid Retina XDR ProMotion smoothness on charger and conserve battery life when portable.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Audio Settings")) {
                Toggle("Mute Audio Track", isOn: $settings.isMuted)
                Text("When muted, the audio track is omitted from decode pipeline to prevent power assertions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("System Integration")) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.isLaunchAtLoginEnabled },
                    set: { settings.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 6: Feature 5 - Smart Pause & Gaming
    
    private var powerTab: some View {
        Form {
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
            
            Section(header: Text("Idle Memory Purge")) {
                HStack {
                    Slider(value: $settings.idleBufferReleaseSeconds, in: 5...60, step: 5)
                    Text("\(Int(settings.idleBufferReleaseSeconds))s")
                        .frame(width: 40, alignment: .trailing)
                }
                Text("Drops hardware decode buffers from RAM when paused.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Tab 7: Diagnostics
    
    private var diagnosticsTab: some View {
        Form {
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
                    Label("Low Power Mode", systemImage: "leaf.fill")
                    Spacer()
                    Text(diagnostics.isLowPowerMode ? "Active" : "Disabled")
                }
                
                HStack {
                    Label("Thermal State", systemImage: "thermometer.medium")
                    Spacer()
                    Text(diagnostics.thermalStateDescription)
                }
            }
            
            Section(header: Text("Active Pause Conditions")) {
                if diagnostics.activePauseReasons.isEmpty {
                    Label("None — Playing normally", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    ForEach(diagnostics.activePauseReasons, id: \.self) { reason in
                        Label(reason, systemImage: "pause.circle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Helpers
    
    private func contentTypeDescription(_ type: WallpaperContentType) -> String {
        switch type {
        case .video:
            return "Zero-copy hardware video decoding via AVFoundation & VideoToolbox."
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
