import Foundation
import AVFoundation
import ServiceManagement
import Combine

public enum DisplayMode: String, CaseIterable, Identifiable, Codable {
    case sameOnAll = "Same on All Displays"
    case perDisplay = "Per Display"
    
    public var id: String { rawValue }
}

public enum TargetFPS: Int, CaseIterable, Identifiable, Codable {
    case fps24 = 24
    case fps30 = 30
    case fps60 = 60
    case fps120 = 120
    case native = 0
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .fps24: return "24 fps (Cinema / Battery Saver)"
        case .fps30: return "30 fps (Default / Balanced)"
        case .fps60: return "60 fps (Smooth Motion)"
        case .fps120: return "120 fps (ProMotion Ultra Smooth)"
        case .native: return "Native Source Framerate"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .fps24: return "24 fps"
        case .fps30: return "30 fps"
        case .fps60: return "60 fps"
        case .fps120: return "120 fps"
        case .native: return "Native"
        }
    }
}

public enum WindowLevelMode: Int, CaseIterable, Identifiable, Codable {
    case desktop = 0
    case belowIcons = 1
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .desktop: return "Desktop Level (Behind Icons & Widgets)"
        case .belowIcons: return "Below Icons Level"
        }
    }
}

// MARK: - Feature 1: Day & Night Mode Types
public enum DayNightTrigger: String, CaseIterable, Identifiable, Codable {
    case systemAppearance = "System Appearance (Dark / Light)"
    case timeOfDay = "Scheduled Time of Day"
    
    public var id: String { rawValue }
}

// MARK: - Feature 2: Multi-Video Playlist Types
public enum PlaylistShuffleMode: String, CaseIterable, Identifiable, Codable {
    case sequential = "In Order (Sequential)"
    case randomShuffle = "Random Shuffle"
    
    public var id: String { rawValue }
}

public enum PlaylistTrigger: String, CaseIterable, Identifiable, Codable {
    case interval = "Timer Interval"
    case onWakeUnlock = "On Wake & Unlock"
    case both = "Timer and Wake / Unlock"
    
    public var id: String { rawValue }
}

// MARK: - Feature 5: Smart Game & Heavy App Types
public enum HeavyAppPauseScope: String, CaseIterable, Identifiable, Codable {
    case frontmostOnly = "Active / Frontmost Window"
    case anyRunning = "Any Running Process"
    
    public var id: String { rawValue }
}

// MARK: - Interactive Content Types (Web / Metal / Particles)
public enum WallpaperContentType: String, CaseIterable, Identifiable, Codable {
    case video = "Video File (.mp4, .mov)"
    case metal = "Native Metal 4 Compute Shaders"
    case web = "Web / HTML / Shaders (WebKit)"
    case particles = "Interactive Procedural Particles"
    
    public var id: String { rawValue }
}

public enum MetalShaderPreset: String, CaseIterable, Identifiable, Codable {
    case nebula = "Deep Space Cosmic Nebula"
    case matrix = "Cyberpunk Digital Rain"
    case fluid = "Minimalist Liquid Fluid"
    case aurora = "Atmospheric Northern Aurora"
    
    public var id: String { rawValue }
}

public enum ParticlePreset: String, CaseIterable, Identifiable, Codable {
    case none = "None (Disabled)"
    case snow = "Gentle Falling Snow"
    case sakura = "Cherry Blossom (Sakura)"
    case rain = "Cinematic Rain & Splash"
    case embers = "Floating Fire Embers"
    case stars = "Deep Space Starfield"
    case matrix = "Cyberpunk Matrix Code"
    
    public var id: String { rawValue }
}

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let defaults = UserDefaults(suiteName: "com.local.LiveWallpaper") ?? UserDefaults.standard
    
    // MARK: - Standard Video & Display Properties
    
    @Published public var videoBookmark: Data? {
        didSet { defaults.set(videoBookmark, forKey: "videoBookmark") }
    }
    
    @Published public var videoPath: String? {
        didSet { defaults.set(videoPath, forKey: "videoPath") }
    }
    
    @Published public var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: "displayMode") }
    }
    
    @Published public var targetFPS: TargetFPS {
        didSet { defaults.set(targetFPS.rawValue, forKey: "targetFPS") }
    }
    
    @Published public var isMuted: Bool {
        didSet { defaults.set(isMuted, forKey: "isMuted") }
    }
    
    @Published public var videoGravity: AVLayerVideoGravity {
        didSet { defaults.set(videoGravity.rawValue, forKey: "videoGravity") }
    }
    
    @Published public var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: "pauseOnBattery") }
    }
    
    @Published public var pauseOnLowPowerMode: Bool {
        didSet { defaults.set(pauseOnLowPowerMode, forKey: "pauseOnLowPowerMode") }
    }
    
    @Published public var pauseWhenOccluded: Bool {
        didSet { defaults.set(pauseWhenOccluded, forKey: "pauseWhenOccluded") }
    }
    
    @Published public var pauseOnThermalThrottling: Bool {
        didSet { defaults.set(pauseOnThermalThrottling, forKey: "pauseOnThermalThrottling") }
    }
    
    @Published public var idleBufferReleaseSeconds: Double {
        didSet { defaults.set(idleBufferReleaseSeconds, forKey: "idleBufferReleaseSeconds") }
    }
    
    @Published public var windowLevelMode: WindowLevelMode {
        didSet { defaults.set(windowLevelMode.rawValue, forKey: "windowLevelMode") }
    }
    
    @Published public var isUserPaused: Bool {
        didSet { defaults.set(isUserPaused, forKey: "isUserPaused") }
    }
    
    @Published public var isLaunchAtLoginEnabled: Bool = false
    
    // MARK: - Feature 1: Day & Night Mode
    
    @Published public var isDayNightEnabled: Bool {
        didSet { defaults.set(isDayNightEnabled, forKey: "isDayNightEnabled") }
    }
    
    @Published public var dayNightTrigger: DayNightTrigger {
        didSet { defaults.set(dayNightTrigger.rawValue, forKey: "dayNightTrigger") }
    }
    
    @Published public var dayVideoPath: String? {
        didSet { defaults.set(dayVideoPath, forKey: "dayVideoPath") }
    }
    
    @Published public var dayVideoBookmark: Data? {
        didSet { defaults.set(dayVideoBookmark, forKey: "dayVideoBookmark") }
    }
    
    @Published public var nightVideoPath: String? {
        didSet { defaults.set(nightVideoPath, forKey: "nightVideoPath") }
    }
    
    @Published public var nightVideoBookmark: Data? {
        didSet { defaults.set(nightVideoBookmark, forKey: "nightVideoBookmark") }
    }
    
    @Published public var dayStartHour: Int {
        didSet { defaults.set(dayStartHour, forKey: "dayStartHour") }
    }
    
    @Published public var nightStartHour: Int {
        didSet { defaults.set(nightStartHour, forKey: "nightStartHour") }
    }
    
    // MARK: - Feature 2: Multi-Video Playlist & Shuffle
    
    @Published public var isPlaylistEnabled: Bool {
        didSet { defaults.set(isPlaylistEnabled, forKey: "isPlaylistEnabled") }
    }
    
    @Published public var playlistVideos: [String] {
        didSet { defaults.set(playlistVideos, forKey: "playlistVideos") }
    }
    
    @Published public var playlistBookmarks: [String: Data] {
        didSet { defaults.set(playlistBookmarks, forKey: "playlistBookmarks") }
    }
    
    @Published public var playlistShuffleMode: PlaylistShuffleMode {
        didSet { defaults.set(playlistShuffleMode.rawValue, forKey: "playlistShuffleMode") }
    }
    
    @Published public var playlistTrigger: PlaylistTrigger {
        didSet { defaults.set(playlistTrigger.rawValue, forKey: "playlistTrigger") }
    }
    
    @Published public var playlistIntervalMinutes: Int {
        didSet { defaults.set(playlistIntervalMinutes, forKey: "playlistIntervalMinutes") }
    }
    
    // MARK: - Feature 3: Per-Display Video Wallpapers
    
    @Published public var perDisplayVideoPaths: [String: String] {
        didSet { defaults.set(perDisplayVideoPaths, forKey: "perDisplayVideoPaths") }
    }
    
    @Published public var perDisplayVideoBookmarks: [String: Data] {
        didSet { defaults.set(perDisplayVideoBookmarks, forKey: "perDisplayVideoBookmarks") }
    }
    
    // MARK: - Feature 4: Playback Speed & Cinematic Slow-Motion
    
    @Published public var playbackSpeed: Double {
        didSet { defaults.set(playbackSpeed, forKey: "playbackSpeed") }
    }
    
    // MARK: - Feature 5: Smart Game & Heavy App Auto-Pause
    
    @Published public var isHeavyAppPauseEnabled: Bool {
        didSet { defaults.set(isHeavyAppPauseEnabled, forKey: "isHeavyAppPauseEnabled") }
    }
    
    @Published public var heavyAppPauseScope: HeavyAppPauseScope {
        didSet { defaults.set(heavyAppPauseScope.rawValue, forKey: "heavyAppPauseScope") }
    }
    
    @Published public var heavyAppIdentifiers: [String] {
        didSet { defaults.set(heavyAppIdentifiers, forKey: "heavyAppIdentifiers") }
    }
    
    // MARK: - Desktop Filters & Readability
    
    @Published public var dimmingAmount: Double {
        didSet { defaults.set(dimmingAmount, forKey: "dimmingAmount") }
    }
    
    @Published public var blurRadius: Double {
        didSet { defaults.set(blurRadius, forKey: "blurRadius") }
    }
    
    @Published public var saturationAmount: Double {
        didSet { defaults.set(saturationAmount, forKey: "saturationAmount") }
    }
    
    @Published public var contrastAmount: Double {
        didSet { defaults.set(contrastAmount, forKey: "contrastAmount") }
    }
    
    // MARK: - Atmosphere & Color Grading Studio
    
    @Published public var vignetteAmount: Double {
        didSet { defaults.set(vignetteAmount, forKey: "vignetteAmount") }
    }
    
    @Published public var exposureAmount: Double {
        didSet { defaults.set(exposureAmount, forKey: "exposureAmount") }
    }
    
    @Published public var widgetReadabilityMode: Bool {
        didSet { defaults.set(widgetReadabilityMode, forKey: "widgetReadabilityMode") }
    }
    
    // MARK: - Auto-Looping & Trimming Magic
    
    @Published public var isAutoLoopCrossfadeEnabled: Bool {
        didSet { defaults.set(isAutoLoopCrossfadeEnabled, forKey: "isAutoLoopCrossfadeEnabled") }
    }
    
    @Published public var crossfadeDuration: Double {
        didSet { defaults.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }
    
    @Published public var isPingPongLoopEnabled: Bool {
        didSet { defaults.set(isPingPongLoopEnabled, forKey: "isPingPongLoopEnabled") }
    }
    
    @Published public var trimStartTime: Double {
        didSet { defaults.set(trimStartTime, forKey: "trimStartTime") }
    }
    
    @Published public var trimEndTime: Double {
        didSet { defaults.set(trimEndTime, forKey: "trimEndTime") }
    }
    
    // MARK: - Dynamic Color Harmony
    
    @Published public var dynamicAccentColorHex: String {
        didSet { defaults.set(dynamicAccentColorHex, forKey: "dynamicAccentColorHex") }
    }
    
    // MARK: - Smart Battery Profiles & MagSafe Adaptivity
    
    @Published public var isAdaptiveFramerateEnabled: Bool {
        didSet { defaults.set(isAdaptiveFramerateEnabled, forKey: "isAdaptiveFramerateEnabled") }
    }
    
    @Published public var acFramerate: TargetFPS {
        didSet { defaults.set(acFramerate.rawValue, forKey: "acFramerate") }
    }
    
    @Published public var batteryHighFramerate: TargetFPS {
        didSet { defaults.set(batteryHighFramerate.rawValue, forKey: "batteryHighFramerate") }
    }
    
    @Published public var batteryLowFramerate: TargetFPS {
        didSet { defaults.set(batteryLowFramerate.rawValue, forKey: "batteryLowFramerate") }
    }
    
    // MARK: - Interactive Content Types & Web/Shader Settings
    
    @Published public var contentType: WallpaperContentType {
        didSet { defaults.set(contentType.rawValue, forKey: "contentType") }
    }
    
    @Published public var metalPreset: MetalShaderPreset {
        didSet { defaults.set(metalPreset.rawValue, forKey: "metalPreset") }
    }
    
    @Published public var webURLString: String? {
        didSet { defaults.set(webURLString, forKey: "webURLString") }
    }
    
    @Published public var selectedWebPreset: String {
        didSet { defaults.set(selectedWebPreset, forKey: "selectedWebPreset") }
    }
    
    // MARK: - Mouse Interactivity & 3D Parallax
    
    @Published public var isMouseInteractionEnabled: Bool {
        didSet { defaults.set(isMouseInteractionEnabled, forKey: "isMouseInteractionEnabled") }
    }
    
    @Published public var parallaxIntensity: Double {
        didSet { defaults.set(parallaxIntensity, forKey: "parallaxIntensity") }
    }
    
    @Published public var parallaxTiltEnabled: Bool {
        didSet { defaults.set(parallaxTiltEnabled, forKey: "parallaxTiltEnabled") }
    }
    
    @Published public var parallaxDepthLayers: Bool {
        didSet { defaults.set(parallaxDepthLayers, forKey: "parallaxDepthLayers") }
    }
    
    @Published public var parallaxLightingSheen: Bool {
        didSet { defaults.set(parallaxLightingSheen, forKey: "parallaxLightingSheen") }
    }
    
    // MARK: - Procedural Particle Engine & Weather Overlays
    
    @Published public var isParticleOverlayEnabled: Bool {
        didSet { defaults.set(isParticleOverlayEnabled, forKey: "isParticleOverlayEnabled") }
    }
    
    @Published public var particlePreset: ParticlePreset {
        didSet { defaults.set(particlePreset.rawValue, forKey: "particlePreset") }
    }
    
    // Default heavy apps list
    public static let defaultHeavyApps: [String] = [
        "com.valvesoftware.steam",
        "com.apple.FinalCut",
        "org.blenderfoundation.blender",
        "com.unity3d.unityeditor",
        "com.epicgames.UnrealEditor",
        "com.apple.dt.Xcode",
        "com.apple.CoreSimulator.CoreSimulatorService",
        "com.apple.logic10",
        "com.adobe.PremierePro",
        "com.adobe.AfterEffects",
        "com.parallels.desktop.console",
        "com.vmware.fusion"
    ]
    
    // MARK: - Initialization
    
    private init() {
        self.videoBookmark = defaults.data(forKey: "videoBookmark")
        self.videoPath = defaults.string(forKey: "videoPath")
        
        let savedDisplayMode = defaults.string(forKey: "displayMode").flatMap(DisplayMode.init) ?? .sameOnAll
        self.displayMode = savedDisplayMode
        
        let savedFPS = defaults.object(forKey: "targetFPS") as? Int
        self.targetFPS = savedFPS.flatMap(TargetFPS.init) ?? .fps120
        
        self.isMuted = defaults.object(forKey: "isMuted") as? Bool ?? true
        
        let savedGravity = defaults.string(forKey: "videoGravity")
        self.videoGravity = savedGravity.map(AVLayerVideoGravity.init(rawValue:)) ?? .resizeAspectFill
        
        self.pauseOnBattery = defaults.object(forKey: "pauseOnBattery") as? Bool ?? false
        self.pauseOnLowPowerMode = defaults.object(forKey: "pauseOnLowPowerMode") as? Bool ?? true
        self.pauseWhenOccluded = defaults.object(forKey: "pauseWhenOccluded") as? Bool ?? false
        self.pauseOnThermalThrottling = defaults.object(forKey: "pauseOnThermalThrottling") as? Bool ?? true
        
        self.idleBufferReleaseSeconds = defaults.object(forKey: "idleBufferReleaseSeconds") as? Double ?? 15.0
        
        let savedWindowLevel = defaults.object(forKey: "windowLevelMode") as? Int
        self.windowLevelMode = savedWindowLevel.flatMap(WindowLevelMode.init) ?? .desktop
        
        self.isUserPaused = defaults.bool(forKey: "isUserPaused")
        
        // Feature 1: Day & Night
        self.isDayNightEnabled = defaults.bool(forKey: "isDayNightEnabled")
        self.dayNightTrigger = defaults.string(forKey: "dayNightTrigger").flatMap(DayNightTrigger.init) ?? .systemAppearance
        self.dayVideoPath = defaults.string(forKey: "dayVideoPath")
        self.dayVideoBookmark = defaults.data(forKey: "dayVideoBookmark")
        self.nightVideoPath = defaults.string(forKey: "nightVideoPath")
        self.nightVideoBookmark = defaults.data(forKey: "nightVideoBookmark")
        self.dayStartHour = defaults.object(forKey: "dayStartHour") as? Int ?? 6
        self.nightStartHour = defaults.object(forKey: "nightStartHour") as? Int ?? 18
        
        // Feature 2: Playlist
        self.isPlaylistEnabled = defaults.bool(forKey: "isPlaylistEnabled")
        self.playlistVideos = defaults.stringArray(forKey: "playlistVideos") ?? []
        self.playlistBookmarks = defaults.dictionary(forKey: "playlistBookmarks") as? [String: Data] ?? [:]
        self.playlistShuffleMode = defaults.string(forKey: "playlistShuffleMode").flatMap(PlaylistShuffleMode.init) ?? .sequential
        self.playlistTrigger = defaults.string(forKey: "playlistTrigger").flatMap(PlaylistTrigger.init) ?? .interval
        self.playlistIntervalMinutes = defaults.object(forKey: "playlistIntervalMinutes") as? Int ?? 30
        
        // Feature 3: Per-Display
        self.perDisplayVideoPaths = defaults.dictionary(forKey: "perDisplayVideoPaths") as? [String: String] ?? [:]
        self.perDisplayVideoBookmarks = defaults.dictionary(forKey: "perDisplayVideoBookmarks") as? [String: Data] ?? [:]
        
        // Feature 4: Playback Speed
        let savedSpeed = defaults.object(forKey: "playbackSpeed") as? Double ?? 1.0
        self.playbackSpeed = savedSpeed > 0 ? savedSpeed : 1.0
        
        // Feature 5: Smart Game & Heavy App
        self.isHeavyAppPauseEnabled = defaults.object(forKey: "isHeavyAppPauseEnabled") as? Bool ?? true
        self.heavyAppPauseScope = defaults.string(forKey: "heavyAppPauseScope").flatMap(HeavyAppPauseScope.init) ?? .frontmostOnly
        self.heavyAppIdentifiers = defaults.stringArray(forKey: "heavyAppIdentifiers") ?? Self.defaultHeavyApps
        
        // Desktop Filters & Readability
        self.dimmingAmount = defaults.object(forKey: "dimmingAmount") as? Double ?? 0.0
        self.blurRadius = defaults.object(forKey: "blurRadius") as? Double ?? 0.0
        self.saturationAmount = defaults.object(forKey: "saturationAmount") as? Double ?? 1.0
        self.contrastAmount = defaults.object(forKey: "contrastAmount") as? Double ?? 1.0
        
        // Atmosphere & Color Grading Studio
        self.vignetteAmount = defaults.object(forKey: "vignetteAmount") as? Double ?? 0.0
        self.exposureAmount = defaults.object(forKey: "exposureAmount") as? Double ?? 0.0
        self.widgetReadabilityMode = defaults.object(forKey: "widgetReadabilityMode") as? Bool ?? true
        
        // Auto-Looping & Trimming Magic
        self.isAutoLoopCrossfadeEnabled = defaults.bool(forKey: "isAutoLoopCrossfadeEnabled")
        self.crossfadeDuration = defaults.object(forKey: "crossfadeDuration") as? Double ?? 1.5
        self.isPingPongLoopEnabled = defaults.bool(forKey: "isPingPongLoopEnabled")
        self.trimStartTime = defaults.object(forKey: "trimStartTime") as? Double ?? 0.0
        self.trimEndTime = defaults.object(forKey: "trimEndTime") as? Double ?? 0.0
        self.dynamicAccentColorHex = defaults.string(forKey: "dynamicAccentColorHex") ?? "#007AFF"
        
        // Smart Battery Profiles
        self.isAdaptiveFramerateEnabled = defaults.object(forKey: "isAdaptiveFramerateEnabled") as? Bool ?? true
        let savedAcFPS = defaults.object(forKey: "acFramerate") as? Int
        self.acFramerate = savedAcFPS.flatMap(TargetFPS.init) ?? .fps120
        let savedBattHigh = defaults.object(forKey: "batteryHighFramerate") as? Int
        self.batteryHighFramerate = savedBattHigh.flatMap(TargetFPS.init) ?? .fps60
        let savedBattLow = defaults.object(forKey: "batteryLowFramerate") as? Int
        self.batteryLowFramerate = savedBattLow.flatMap(TargetFPS.init) ?? .fps24
        
        // Interactive Content Types
        self.contentType = defaults.string(forKey: "contentType").flatMap(WallpaperContentType.init) ?? .video
        self.metalPreset = defaults.string(forKey: "metalPreset").flatMap(MetalShaderPreset.init) ?? .nebula
        self.webURLString = defaults.string(forKey: "webURLString")
        self.selectedWebPreset = defaults.string(forKey: "selectedWebPreset") ?? "Cyberpunk Matrix"
        
        // Mouse Interactivity & 3D Parallax
        self.isMouseInteractionEnabled = defaults.object(forKey: "isMouseInteractionEnabled") as? Bool ?? true
        self.parallaxIntensity = defaults.object(forKey: "parallaxIntensity") as? Double ?? 0.35
        self.parallaxTiltEnabled = defaults.object(forKey: "parallaxTiltEnabled") as? Bool ?? true
        self.parallaxDepthLayers = defaults.object(forKey: "parallaxDepthLayers") as? Bool ?? true
        self.parallaxLightingSheen = defaults.object(forKey: "parallaxLightingSheen") as? Bool ?? true
        
        // Procedural Particles & Weather Overlays
        self.isParticleOverlayEnabled = defaults.bool(forKey: "isParticleOverlayEnabled")
        self.particlePreset = defaults.string(forKey: "particlePreset").flatMap(ParticlePreset.init) ?? .snow
        
        refreshLaunchAtLoginStatus()
    }
    
    public func refreshLaunchAtLoginStatus() {
        Task {
            let status = SMAppService.mainApp.status == .enabled
            if self.isLaunchAtLoginEnabled != status {
                self.isLaunchAtLoginEnabled = status
            }
        }
    }
    
    public func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try await SMAppService.mainApp.unregister()
                    }
                }
                let currentStatus = SMAppService.mainApp.status == .enabled
                self.isLaunchAtLoginEnabled = currentStatus
            } catch {
                NSLog("[AppSettings] Error toggling launch at login: \(error.localizedDescription)")
            }
        }
    }
}
