import Foundation
import AVFoundation
import AppKit
import Combine

public enum PlaylistDirection {
    case next
    case previous
}

@MainActor
public final class PlaybackCoordinator: NSObject, ResourceMonitorDelegate, VideoEngineDelegate {
    public static let shared = PlaybackCoordinator()
    
    public let primaryEngine = VideoEngine()
    public private(set) var perDisplayEngines: [CGDirectDisplayID: VideoEngine] = [:]
    
    public let resourceMonitor = ResourceMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    // Feature 1: Day & Night timer
    private var dayNightCheckTimer: Timer?
    
    // Feature 2: Playlist state & timer
    public private(set) var currentPlaylistIndex: Int = 0
    private var playlistTimer: Timer?
    
    private override init() {
        super.init()
        primaryEngine.delegate = self
        resourceMonitor.delegate = self
    }
    
    public func start() {
        setupSettingsBinding()
        resourceMonitor.start()
        startDayNightTimer()
        reconfigurePlaylistTimer()
        evaluateAdaptiveFramerate()
        loadPersistedVideo()
        rebuildPerDisplayEngines()
    }
    
    // MARK: - Settings Bindings
    
    private func setupSettingsBinding() {
        let settings = AppSettings.shared
        
        // Target FPS
        settings.$targetFPS
            .dropFirst()
            .sink { [weak self] fps in
                Task { @MainActor in
                    guard let self = self else { return }
                    await self.primaryEngine.updateFramerate(fps)
                    for engine in self.perDisplayEngines.values {
                        await engine.updateFramerate(fps)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Audio Mute
        settings.$isMuted
            .dropFirst()
            .sink { [weak self] muted in
                guard let self = self else { return }
                self.primaryEngine.setMuted(muted)
                for engine in self.perDisplayEngines.values {
                    engine.setMuted(muted)
                }
            }
            .store(in: &cancellables)
        
        // Feature 4: Playback Speed
        settings.$playbackSpeed
            .dropFirst()
            .sink { [weak self] speed in
                guard let self = self else { return }
                self.primaryEngine.setPlaybackSpeed(speed)
                for engine in self.perDisplayEngines.values {
                    engine.setPlaybackSpeed(speed)
                }
            }
            .store(in: &cancellables)
            
        // Trimming & Range updates
        Publishers.Merge(
            settings.$trimStartTime.dropFirst().map { _ in () },
            settings.$trimEndTime.dropFirst().map { _ in () }
        )
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                await self?.primaryEngine.reconfigureTrimming()
            }
        }
        .store(in: &cancellables)
        
        // Resource / Power / Heavy App triggers
        Publishers.Merge5(
            settings.$pauseOnBattery.dropFirst(),
            settings.$pauseOnLowPowerMode.dropFirst(),
            settings.$pauseWhenOccluded.dropFirst(),
            settings.$pauseOnThermalThrottling.dropFirst(),
            settings.$isHeavyAppPauseEnabled.dropFirst()
        )
        .sink { [weak self] _ in
            self?.resourceMonitor.evaluateAllConditions()
        }
        .store(in: &cancellables)
        
        Publishers.Merge(
            settings.$heavyAppPauseScope.dropFirst().map { _ in () },
            settings.$heavyAppIdentifiers.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.resourceMonitor.evaluateAllConditions()
        }
        .store(in: &cancellables)
        
        // Feature 1: Day & Night Mode triggers
        Publishers.Merge4(
            settings.$isDayNightEnabled.dropFirst().map { _ in () },
            settings.$dayNightTrigger.dropFirst().map { _ in () },
            settings.$dayVideoPath.dropFirst().map { _ in () },
            settings.$nightVideoPath.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.evaluateDayNightMode()
        }
        .store(in: &cancellables)
        
        // Feature 2: Playlist triggers
        Publishers.Merge4(
            settings.$isPlaylistEnabled.dropFirst().map { _ in () },
            settings.$playlistShuffleMode.dropFirst().map { _ in () },
            settings.$playlistTrigger.dropFirst().map { _ in () },
            settings.$playlistIntervalMinutes.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.reconfigurePlaylistTimer()
        }
        .store(in: &cancellables)
        
        // Feature 3: Per-Display triggers
        Publishers.Merge(
            settings.$displayMode.dropFirst().map { _ in () },
            settings.$perDisplayVideoPaths.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.rebuildPerDisplayEngines()
        }
        .store(in: &cancellables)
        
        // Feature 4: Smart Battery Profiles & MagSafe Adaptivity
        Publishers.Merge4(
            settings.$isAdaptiveFramerateEnabled.dropFirst().map { _ in () },
            settings.$acFramerate.dropFirst().map { _ in () },
            settings.$batteryHighFramerate.dropFirst().map { _ in () },
            settings.$batteryLowFramerate.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.evaluateAdaptiveFramerate()
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Video Persistence & Loading
    
    private func loadPersistedVideo() {
        let settings = AppSettings.shared
        
        // Priority 1: Day & Night mode if active
        if settings.isDayNightEnabled {
            if evaluateDayNightMode() {
                return
            }
        }
        
        // Priority 2: Playlist if active
        if settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty {
            if loadPlaylistVideo(at: currentPlaylistIndex) {
                return
            }
        }
        
        // Priority 3: Saved primary bookmark or path
        if let bookmarkData = settings.videoBookmark {
            if let result = SecurityBookmarkManager.shared.resolveBookmark(bookmarkData) {
                loadVideo(url: result.url)
                return
            }
        }
        
        if let path = settings.videoPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                loadVideo(url: url)
            }
        }
    }
    
    public var primaryDisplayID: CGDirectDisplayID {
        let screens = NSScreen.screens
        let primary = screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? screens.first
        return primary?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
    
    public func play() {
        primaryEngine.play()
        for engine in perDisplayEngines.values {
            engine.play()
        }
    }
    
    public func pause() {
        primaryEngine.pause()
        for engine in perDisplayEngines.values {
            engine.pause()
        }
    }
    
    public func loadVideo(url: URL, syncScreenSaver: Bool = true) {
        let settings = AppSettings.shared
        
        if let bookmark = SecurityBookmarkManager.shared.createBookmark(for: url) {
            settings.videoBookmark = bookmark
        }
        settings.videoPath = url.path
        
        Task { @MainActor in
            await primaryEngine.loadVideo(
                url: url,
                targetFPS: settings.targetFPS,
                isMuted: settings.isMuted,
                playbackSpeed: settings.playbackSpeed
            )
            
            // Sync lock screen poster frame AND native 120Hz aerial screen saver
            if syncScreenSaver, let asset = primaryEngine.currentAsset {
                LockScreenPosterManager.shared.updateLockScreenPoster(for: asset, at: .zero)
                LockScreenPosterManager.shared.syncScreenSaverVideo(from: url, asset: asset)
            }
            
            // Rebuild/update secondary engines so all monitors receive a dedicated hardware stream
            await updateSecondaryEngines(url: url)
            
            resourceMonitor.evaluateAllConditions()
            
            if resourceMonitor.activePauseReasons.isEmpty {
                play()
            }
            
            WindowManager.shared.reconnectPlayers(coordinator: self)
        }
    }
    
    // MARK: - Feature 1: Day & Night Mode Engine
    
    private func startDayNightTimer() {
        dayNightCheckTimer?.invalidate()
        // Check time-of-day changes every 30 seconds
        dayNightCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateDayNightMode()
            }
        }
    }
    
    @discardableResult
    public func evaluateDayNightMode() -> Bool {
        let settings = AppSettings.shared
        guard settings.isDayNightEnabled else { return false }
        
        let isNight: Bool
        switch settings.dayNightTrigger {
        case .systemAppearance:
            isNight = ResourceMonitor.isDarkMode()
        case .timeOfDay:
            let hour = Calendar.current.component(.hour, from: Date())
            if settings.nightStartHour > settings.dayStartHour {
                isNight = (hour >= settings.nightStartHour || hour < settings.dayStartHour)
            } else {
                isNight = (hour >= settings.nightStartHour && hour < settings.dayStartHour)
            }
        }
        
        let targetPath = isNight ? settings.nightVideoPath : settings.dayVideoPath
        guard let path = targetPath, !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            return false
        }
        
        let targetURL = URL(fileURLWithPath: path)
        if primaryEngine.videoURL?.standardizedFileURL != targetURL.standardizedFileURL {
            NSLog("[PlaybackCoordinator] Day/Night Mode switching to \(isNight ? "Night" : "Day") video: \(path)")
            loadVideo(url: targetURL)
            return true
        }
        return false
    }
    
    // MARK: - Feature 2: Multi-Video Playlist Engine
    
    public func reconfigurePlaylistTimer() {
        playlistTimer?.invalidate()
        playlistTimer = nil
        
        let settings = AppSettings.shared
        guard settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty else { return }
        
        let interval = Double(max(1, settings.playlistIntervalMinutes) * 60)
        if settings.playlistTrigger == .interval || settings.playlistTrigger == .both {
            playlistTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.advancePlaylist(direction: .next)
                }
            }
        }
    }
    
    public func advancePlaylist(direction: PlaylistDirection = .next) {
        let settings = AppSettings.shared
        let videos = settings.playlistVideos
        guard !videos.isEmpty else { return }
        
        if settings.playlistShuffleMode == .randomShuffle && videos.count > 1 {
            var newIndex = currentPlaylistIndex
            while newIndex == currentPlaylistIndex {
                newIndex = Int.random(in: 0..<videos.count)
            }
            currentPlaylistIndex = newIndex
        } else {
            if direction == .next {
                currentPlaylistIndex = (currentPlaylistIndex + 1) % videos.count
            } else {
                currentPlaylistIndex = (currentPlaylistIndex - 1 + videos.count) % videos.count
            }
        }
        
        _ = loadPlaylistVideo(at: currentPlaylistIndex)
    }
    
    @discardableResult
    private func loadPlaylistVideo(at index: Int) -> Bool {
        let settings = AppSettings.shared
        let videos = settings.playlistVideos
        guard index >= 0 && index < videos.count else { return false }
        
        let path = videos[index]
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("[PlaybackCoordinator] Playlist video file not found: \(path)")
            return false
        }
        
        currentPlaylistIndex = index
        loadVideo(url: url)
        return true
    }
    
    public func addVideosToPlaylist(urls: [URL]) {
        let settings = AppSettings.shared
        var currentList = settings.playlistVideos
        var bookmarks = settings.playlistBookmarks
        
        for url in urls {
            let path = url.path
            if !currentList.contains(path) {
                currentList.append(path)
                if let bookmark = SecurityBookmarkManager.shared.createBookmark(for: url) {
                    bookmarks[path] = bookmark
                }
            }
        }
        
        settings.playlistVideos = currentList
        settings.playlistBookmarks = bookmarks
        reconfigurePlaylistTimer()
    }
    
    public func removeVideoFromPlaylist(at index: Int) {
        let settings = AppSettings.shared
        guard index >= 0 && index < settings.playlistVideos.count else { return }
        
        let removedPath = settings.playlistVideos[index]
        settings.playlistVideos.remove(at: index)
        settings.playlistBookmarks.removeValue(forKey: removedPath)
        
        if currentPlaylistIndex >= settings.playlistVideos.count {
            currentPlaylistIndex = max(0, settings.playlistVideos.count - 1)
        }
        reconfigurePlaylistTimer()
    }
    
    // MARK: - Feature 3: Per-Display Custom Wallpapers Engine
    
    public func rebuildPerDisplayEngines() {
        guard let url = primaryEngine.videoURL else { return }
        Task { @MainActor in
            await updateSecondaryEngines(url: url)
        }
    }
    
    public func updateSecondaryEngines(url: URL) async {
        let settings = AppSettings.shared
        let currentScreens = NSScreen.screens
        let currentDisplayIDs = Set(currentScreens.compactMap { screen -> CGDirectDisplayID? in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        })
        let primaryID = self.primaryDisplayID
        
        // Remove detached display engines or engine if assigned to primary
        for (displayID, engine) in perDisplayEngines {
            if !currentDisplayIDs.contains(displayID) || displayID == primaryID {
                engine.tearDown()
                perDisplayEngines.removeValue(forKey: displayID)
            }
        }
        
        // Optimize decoder resources: If using the same video on all displays,
        // share primaryEngine.player across all displays to avoid duplicate 4K/120Hz decoding
        // and eliminate hardware decoder contention with iPhone Mirroring.
        if settings.displayMode != .perDisplay {
            for (_, engine) in perDisplayEngines {
                engine.tearDown()
            }
            perDisplayEngines.removeAll()
            WindowManager.shared.reconnectPlayers(coordinator: self)
            return
        }
        
        // Ensure every secondary display has its own dedicated hardware-accelerated VideoEngine only in perDisplay mode
        for displayID in currentDisplayIDs where displayID != primaryID {
            let key = String(displayID)
            let targetURL: URL
            if settings.displayMode == .perDisplay,
               let customPath = settings.perDisplayVideoPaths[key],
               FileManager.default.fileExists(atPath: customPath) {
                targetURL = URL(fileURLWithPath: customPath)
            } else {
                targetURL = url
            }
            
            let engine: VideoEngine
            if let existing = perDisplayEngines[displayID] {
                engine = existing
            } else {
                let newEngine = VideoEngine()
                newEngine.delegate = self
                perDisplayEngines[displayID] = newEngine
                engine = newEngine
            }
            
            await engine.loadVideo(
                url: targetURL,
                targetFPS: settings.targetFPS,
                isMuted: true, // Secondary displays are muted by default to eliminate audio echo
                playbackSpeed: settings.playbackSpeed
            )
            
            if resourceMonitor.activePauseReasons.isEmpty {
                engine.play()
            }
        }
        
        WindowManager.shared.reconnectPlayers(coordinator: self)
    }
    
    public func setVideoForDisplay(url: URL, displayID: CGDirectDisplayID) {
        let settings = AppSettings.shared
        let key = String(displayID)
        
        var paths = settings.perDisplayVideoPaths
        paths[key] = url.path
        settings.perDisplayVideoPaths = paths
        
        if let bookmark = SecurityBookmarkManager.shared.createBookmark(for: url) {
            var bookmarks = settings.perDisplayVideoBookmarks
            bookmarks[key] = bookmark
            settings.perDisplayVideoBookmarks = bookmarks
        }
        
        rebuildPerDisplayEngines()
    }
    
    public func clearVideoForDisplay(displayID: CGDirectDisplayID) {
        let settings = AppSettings.shared
        let key = String(displayID)
        
        var paths = settings.perDisplayVideoPaths
        paths.removeValue(forKey: key)
        settings.perDisplayVideoPaths = paths
        
        var bookmarks = settings.perDisplayVideoBookmarks
        bookmarks.removeValue(forKey: key)
        settings.perDisplayVideoBookmarks = bookmarks
        
        rebuildPerDisplayEngines()
    }
    
    // MARK: - Resource & Playback Control
    
    public func togglePlayPause() {
        let settings = AppSettings.shared
        settings.isUserPaused.toggle()
        resourceMonitor.evaluateAllConditions()
    }
    
    public func toggleMute() {
        AppSettings.shared.isMuted.toggle()
    }
    
    public func setFramerate(_ fps: TargetFPS) {
        AppSettings.shared.targetFPS = fps
    }
    
    public func setPlaybackSpeed(_ speed: Double) {
        AppSettings.shared.playbackSpeed = speed
    }
    
    public func seek(toFraction fraction: Double) {
        primaryEngine.seek(toFraction: fraction)
        for engine in perDisplayEngines.values {
            engine.seek(toFraction: fraction)
        }
    }
    
    public func seek(to time: CMTime) {
        primaryEngine.seek(to: time)
        for engine in perDisplayEngines.values {
            engine.seek(to: time)
        }
    }
    
    public func resourceMonitorDidChangePauseState(activeReasons: Set<PauseReason>) {
        if activeReasons.isEmpty {
            WindowManager.shared.setWindowsVisible(true)
            WindowManager.shared.setDisplayLinkActive(true)
            WindowManager.shared.resumeInteractiveLayers()
            if AppSettings.shared.isMouseInteractionEnabled {
                MouseMotionTracker.shared.start()
            }
            primaryEngine.play()
            for engine in perDisplayEngines.values {
                engine.play()
            }
        } else {
            primaryEngine.pause()
            for engine in perDisplayEngines.values {
                engine.pause()
            }
            WindowManager.shared.setDisplayLinkActive(false)
            WindowManager.shared.pauseInteractiveLayers()
            MouseMotionTracker.shared.stop()
            
            // Deep zero-discharge sleep: if screen is off, Mac is asleep, or lid closed,
            // immediately purge all VideoToolbox buffers and unmap window surfaces!
            if activeReasons.contains(.screenAsleep) || activeReasons.contains(.systemAsleep) || activeReasons.contains(.clamshellClosed) {
                primaryEngine.releaseBuffers()
                for engine in perDisplayEngines.values {
                    engine.releaseBuffers()
                }
                WindowManager.shared.setWindowsVisible(false)
            }
            
            // If paused specifically due to lock screen, update lock screen wallpaper with current paused frame
            if activeReasons.contains(.screenLocked) {
                if let asset = primaryEngine.currentAsset {
                    LockScreenPosterManager.shared.updateLockScreenPoster(for: asset, at: primaryEngine.currentTime)
                }
            }
        }
    }
    
    public func resourceMonitorDidTriggerIdleBufferRelease() {
        // Deep sleep safety: Only release hardware buffers if the display is physically sleeping
        // or lid closed. NEVER purge video buffers while the desktop wallpaper is visible or paused,
        // ensuring the paused video frame remains permanently visible without black screen.
        let reasons = resourceMonitor.activePauseReasons
        if reasons.contains(.screenAsleep) || reasons.contains(.systemAsleep) || reasons.contains(.clamshellClosed) {
            primaryEngine.releaseBuffers()
            for engine in perDisplayEngines.values {
                engine.releaseBuffers()
            }
        }
    }
    
    public func resourceMonitorDidDetectAppearanceChange() {
        let settings = AppSettings.shared
        if settings.isDayNightEnabled && settings.dayNightTrigger == .systemAppearance {
            evaluateDayNightMode()
        }
    }
    
    public func resourceMonitorDidWakeOrUnlock() {
        evaluateAdaptiveFramerate()
        let settings = AppSettings.shared
        if settings.isDayNightEnabled {
            evaluateDayNightMode()
        }
        if settings.isPlaylistEnabled && (settings.playlistTrigger == .onWakeUnlock || settings.playlistTrigger == .both) {
            advancePlaylist(direction: .next)
        }
    }
    
    public func resourceMonitorDidUpdatePowerProfile() {
        evaluateAdaptiveFramerate()
    }
    
    // MARK: - Smart Battery Profiles & MagSafe Adaptivity Engine
    
    public func evaluateAdaptiveFramerate() {
        let settings = AppSettings.shared
        guard settings.isAdaptiveFramerateEnabled else { return }
        
        let target: TargetFPS
        if ResourceMonitor.isOnBatteryPower() {
            let percentage = ResourceMonitor.getBatteryPercentage() ?? 100
            if percentage <= 30 || ProcessInfo.processInfo.isLowPowerModeEnabled {
                target = settings.batteryLowFramerate
            } else {
                target = settings.batteryHighFramerate
            }
        } else {
            target = settings.acFramerate
        }
        
        if settings.targetFPS != target {
            NSLog("[PlaybackCoordinator] Adaptive Framerate switching to \(target.shortTitle)")
            settings.targetFPS = target
        }
    }
    
    public func videoEngineDidChangeState(_ engine: VideoEngine, isPlaying: Bool) {}
    
    public func videoEngineDidEncounterError(_ engine: VideoEngine, error: Error) {
        NSLog("[PlaybackCoordinator] Video error: \(error.localizedDescription)")
    }
    
    public func tearDown() {
        dayNightCheckTimer?.invalidate()
        dayNightCheckTimer = nil
        playlistTimer?.invalidate()
        playlistTimer = nil
        resourceMonitor.stop()
        primaryEngine.tearDown()
        for engine in perDisplayEngines.values {
            engine.tearDown()
        }
        perDisplayEngines.removeAll()
    }
}
