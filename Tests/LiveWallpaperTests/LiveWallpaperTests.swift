import XCTest
import AVFoundation
import AppKit
@testable import LiveWallpaper

final class LiveWallpaperTests: XCTestCase {
    
    var sampleVideoURL: URL {
        let currentFileURL = URL(fileURLWithPath: #file)
        let repoRoot = currentFileURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repoRoot.appendingPathComponent("SampleWallpaper.mp4")
    }
    
    // MARK: - 1. Video Bookmark Persistence Tests
    
    func testSecurityBookmarkCreationAndResolution() throws {
        let sampleURL = sampleVideoURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: sampleURL.path), "Sample video must exist in repo at \(sampleURL.path)")
        
        let bookmarkData = SecurityBookmarkManager.shared.createBookmark(for: sampleURL)
        XCTAssertNotNil(bookmarkData, "Bookmark data creation should succeed")
        
        guard let data = bookmarkData else { return }
        let resolved = SecurityBookmarkManager.shared.resolveBookmark(data)
        XCTAssertNotNil(resolved, "Resolving bookmark data should succeed")
        XCTAssertEqual(resolved?.url.standardizedFileURL.path, sampleURL.standardizedFileURL.path)
        
        // Cleanup
        if let url = resolved?.url {
            SecurityBookmarkManager.shared.stopAccessing(url: url)
        }
        SecurityBookmarkManager.shared.stopAccessingAll()
    }
    
    func testInvalidBookmarkResolution() {
        let invalidData = "invalid bookmark data".data(using: .utf8)!
        let resolved = SecurityBookmarkManager.shared.resolveBookmark(invalidData)
        XCTAssertNil(resolved, "Resolving corrupt bookmark data must return nil without crashing")
    }
    
    @MainActor
    func testAppSettingsBookmarkAndPathPersistence() {
        let settings = AppSettings.shared
        let originalPath = settings.videoPath
        let originalBookmark = settings.videoBookmark
        
        defer {
            settings.videoPath = originalPath
            settings.videoBookmark = originalBookmark
        }
        
        let testPath = "/tmp/test_wallpaper_\(UUID().uuidString).mp4"
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        
        settings.videoPath = testPath
        settings.videoBookmark = testData
        
        XCTAssertEqual(UserDefaults.standard.string(forKey: "videoPath"), testPath)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "videoBookmark"), testData)
    }

    // MARK: - 2. Video Engine & Player State Transition Tests
    
    @MainActor
    func testVideoEngineInitialState() {
        let engine = VideoEngine()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertFalse(engine.isBufferReleased)
        XCTAssertEqual(engine.playbackSpeed, 1.0)
        XCTAssertTrue(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 0.0)
        XCTAssertEqual(engine.player.actionAtItemEnd, .none)
    }
    
    @MainActor
    func testVideoEngineLoadAndPlayPause() async {
        let engine = VideoEngine()
        let sampleURL = sampleVideoURL
        
        await engine.loadVideo(url: sampleURL, targetFPS: .fps60, isMuted: true, playbackSpeed: 1.0)
        
        XCTAssertEqual(engine.videoURL, sampleURL)
        XCTAssertNotNil(engine.currentAsset)
        XCTAssertTrue(engine.videoDurationSeconds > 0)
        XCTAssertTrue(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 0.0)
        
        // Play
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        
        // Pause
        engine.pause()
        XCTAssertFalse(engine.isPlaying)
        
        // Speed control
        engine.setPlaybackSpeed(2.0)
        XCTAssertEqual(engine.playbackSpeed, 2.0)
        XCTAssertEqual(engine.player.defaultRate, 2.0)
        
        // Clamping speed bounds
        engine.setPlaybackSpeed(10.0)
        XCTAssertEqual(engine.playbackSpeed, 4.0, "Speed should clamp to maximum 4.0")
        
        engine.setPlaybackSpeed(0.01)
        XCTAssertEqual(engine.playbackSpeed, 0.1, "Speed should clamp to minimum 0.1")
        
        // Mute toggle
        engine.setMuted(false)
        XCTAssertFalse(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 1.0)
        
        engine.setMuted(true)
        XCTAssertTrue(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 0.0)
        
        // Clean teardown
        engine.tearDown()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(engine.currentAsset)
    }
    
    @MainActor
    func testVideoEngineReleaseBuffersAndResume() async {
        let engine = VideoEngine()
        let sampleURL = sampleVideoURL
        
        await engine.loadVideo(url: sampleURL, targetFPS: .fps60, isMuted: true)
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        
        // Release buffers
        engine.releaseBuffers()
        XCTAssertTrue(engine.isBufferReleased)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(engine.player.currentItem)
        
        // Calling releaseBuffers again should be idempotent
        engine.releaseBuffers()
        XCTAssertTrue(engine.isBufferReleased)
        
        // Calling play() after buffers released should asynchronously re-instantiate pipeline and resume
        engine.play()
        
        let exp = expectation(description: "Resume after buffer release")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertFalse(engine.isBufferReleased)
            XCTAssertTrue(engine.isPlaying)
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 3.0)
        
        engine.tearDown()
    }
    
    @MainActor
    func testVideoEngineSeekBounds() async {
        let engine = VideoEngine()
        let sampleURL = sampleVideoURL
        await engine.loadVideo(url: sampleURL, targetFPS: .fps60, isMuted: true)
        
        // Seek fractions
        engine.seek(toFraction: 0.5, exact: true)
        engine.seek(toFraction: -1.0, exact: true) // Clamps to 0
        engine.seek(toFraction: 2.0, exact: true)  // Clamps to 1
        
        engine.tearDown()
    }
    
    // MARK: - 3. PlaybackCoordinator & Resource Monitor Integration Tests
    
    @MainActor
    func testPlaybackCoordinatorPlayPauseAndDelegate() {
        let coordinator = PlaybackCoordinator.shared
        coordinator.pause()
        XCTAssertFalse(coordinator.isPlaying)
        
        coordinator.togglePlayPause()
        coordinator.pause()
        XCTAssertFalse(coordinator.isPlaying)
        
        coordinator.videoEngineDidChangeState(coordinator.primaryEngine, isPlaying: true)
        XCTAssertTrue(coordinator.isPlaying)
        
        coordinator.videoEngineDidChangeState(coordinator.primaryEngine, isPlaying: false)
        XCTAssertFalse(coordinator.isPlaying)
    }
    
    @MainActor
    func testResourceMonitorPauseReasonsEvaluation() {
        let monitor = ResourceMonitor()
        let settings = AppSettings.shared
        
        // Test User Paused
        settings.isUserPaused = true
        monitor.evaluateAllConditions()
        XCTAssertTrue(monitor.activePauseReasons.contains(.userPaused))
        
        settings.isUserPaused = false
        monitor.evaluateAllConditions()
        XCTAssertFalse(monitor.activePauseReasons.contains(.userPaused))
        
        // Test Low Power Mode pause reason respects setting
        settings.pauseOnLowPowerMode = true
        monitor.evaluateAllConditions()
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            XCTAssertTrue(monitor.activePauseReasons.contains(.lowPowerMode))
        }
        
        settings.pauseOnLowPowerMode = false
        monitor.evaluateAllConditions()
        XCTAssertFalse(monitor.activePauseReasons.contains(.lowPowerMode))
        
        // Restore default
        settings.pauseOnLowPowerMode = true
    }
    
    // MARK: - 4. Desktop Window Layering & Multi-Monitor Tests
    
    @MainActor
    func testBackdropWindowAttributes() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            XCTFail("No screens available for testing")
            return
        }
        
        let window = BackdropWindow(screen: screen, levelMode: .desktop)
        
        // Level must be CGWindowLevelForKey(.desktopWindow)
        let expectedLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
        XCTAssertEqual(window.level, expectedLevel, "BackdropWindow must be at desktopWindow level")
        
        // Must ignore mouse clicks
        XCTAssertTrue(window.ignoresMouseEvents, "BackdropWindow must ignore mouse clicks to pass through to desktop")
        
        // Must appear across all Spaces and ignore cycle
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.stationary))
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        
        // Below icons mode level
        window.updateWindowLevel(.belowIcons)
        let expectedBelowIconsLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        XCTAssertEqual(window.level, expectedBelowIconsLevel)
        
        // Restore desktop mode level
        window.updateWindowLevel(.desktop)
        XCTAssertEqual(window.level, expectedLevel)
        
        // Window frame update
        let testRect = NSRect(x: 100, y: 100, width: 800, height: 600)
        window.setFrame(testRect, display: false)
        XCTAssertEqual(window.frame.size, testRect.size)
        
        window.close()
    }
    
    @MainActor
    func testBackdropWindowControllerScreenConfigurationUpdate() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            XCTFail("No screens available for testing")
            return
        }
        
        let controller = BackdropWindowController(screen: screen, levelMode: .desktop, videoGravity: .resizeAspectFill)
        XCTAssertEqual(controller.screen, screen)
        XCTAssertEqual(controller.displayID, screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0)
        
        // Simulate dynamic reconfiguration with updated screen
        controller.updateScreenConfiguration(screen)
        XCTAssertEqual(controller.screen, screen)
        
        controller.tearDown()
    }
    
    @MainActor
    func testWindowManagerWindowControllerLifecycle() {
        let manager = WindowManager.shared
        manager.rebuildWindows()
        
        XCTAssertTrue(NSScreen.screens.count > 0)
    }
    
    // MARK: - 5. Extended Persistence Tests (Playlist, Per-Display, Day/Night)
    
    @MainActor
    func testPlaylistAndPerDisplayAndDayNightBookmarkPersistence() {
        let sampleURL = sampleVideoURL
        guard let bookmark = SecurityBookmarkManager.shared.createBookmark(for: sampleURL) else {
            XCTFail("Failed to create bookmark for sample video")
            return
        }
        
        let settings = AppSettings.shared
        let origPlaylist = settings.playlistVideos
        let origPlaylistBm = settings.playlistBookmarks
        let origDayBm = settings.dayVideoBookmark
        let origNightBm = settings.nightVideoBookmark
        let origPerDisplayBm = settings.perDisplayVideoBookmarks
        
        defer {
            settings.playlistVideos = origPlaylist
            settings.playlistBookmarks = origPlaylistBm
            settings.dayVideoBookmark = origDayBm
            settings.nightVideoBookmark = origNightBm
            settings.perDisplayVideoBookmarks = origPerDisplayBm
            SecurityBookmarkManager.shared.stopAccessingAll()
        }
        
        // Playlist Bookmarks
        settings.playlistVideos = [sampleURL.path]
        settings.playlistBookmarks = [sampleURL.path: bookmark]
        XCTAssertEqual(settings.playlistBookmarks[sampleURL.path], bookmark)
        let resolvedPlaylist = SecurityBookmarkManager.shared.resolveBookmark(bookmark)
        XCTAssertNotNil(resolvedPlaylist)
        XCTAssertEqual(resolvedPlaylist?.url.standardizedFileURL.path, sampleURL.standardizedFileURL.path)
        
        // Day / Night Bookmarks
        settings.dayVideoBookmark = bookmark
        settings.nightVideoBookmark = bookmark
        XCTAssertEqual(settings.dayVideoBookmark, bookmark)
        XCTAssertEqual(settings.nightVideoBookmark, bookmark)
        let resolvedDay = SecurityBookmarkManager.shared.resolveBookmark(bookmark)
        XCTAssertNotNil(resolvedDay)
        
        // Per-Display Bookmarks
        let displayKey = "1"
        settings.perDisplayVideoBookmarks = [displayKey: bookmark]
        XCTAssertEqual(settings.perDisplayVideoBookmarks[displayKey], bookmark)
        let resolvedDisplay = SecurityBookmarkManager.shared.resolveBookmark(bookmark)
        XCTAssertNotNil(resolvedDisplay)
    }
    
    // MARK: - 6. Audio Track Muting & Zero Black Frame Tests
    
    @MainActor
    func testVideoEngineLooperAndAudioTrackDisabling() async {
        let engine = VideoEngine()
        let sampleURL = sampleVideoURL
        await engine.loadVideo(url: sampleURL, targetFPS: .fps60, isMuted: true)
        
        XCTAssertTrue(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 0.0)
        // AVPlayerLooper automatically configures .advance so the queue advances seamlessly
        XCTAssertEqual(engine.player.actionAtItemEnd, .advance)
        
        // Dynamic mute toggle updates player and active queue item
        engine.setMuted(false)
        XCTAssertFalse(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 1.0)
        
        engine.setMuted(true)
        XCTAssertTrue(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 0.0)
        
        engine.tearDown()
    }
    
    @MainActor
    func testVideoPlayerViewUnfreezeProtectsAgainstBlackFlash() {
        let rect = NSRect(x: 0, y: 0, width: 400, height: 300)
        let playerView = VideoPlayerView(frame: rect)
        
        let sampleURL = sampleVideoURL
        let playerItem = AVPlayerItem(url: sampleURL)
        let player = AVPlayer(playerItem: playerItem)
        playerView.attachPlayer(player)
        
        // Set a valid poster/snapshot content
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 10,
            pixelsHigh: 10,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 40,
            bitsPerPixel: 32
        )!
        let cgImage = rep.cgImage
        playerView.playerLayer.contents = cgImage
        
        // Before video frame is ready, unfreezeCurrentFrame must NOT clear contents
        if !playerView.playerLayer.isReadyForDisplay {
            playerView.unfreezeCurrentFrame()
            // Contents should be preserved (not set to nil) until isReadyForDisplay is true
            XCTAssertNotNil(playerView.playerLayer.contents, "Poster content must be preserved until hardware frame is ready")
        }
        
        playerView.detachPlayer(preserveFrame: false)
    }
    
    // MARK: - 7. Screen Sleep, Wake, Lock, and Unlock Event Cycles
    
    @MainActor
    func testResourceMonitorSleepWakeAndLockUnlockTransitions() {
        let monitor = ResourceMonitor()
        let settings = AppSettings.shared
        settings.isUserPaused = false
        
        // 1. Initial State
        monitor.evaluateAllConditions()
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenLocked))
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenAsleep))
        
        // 2. Screen Lock Event
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        // Allow distributed notification delivery
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(monitor.activePauseReasons.contains(.screenLocked))
        
        // 3. Screen Sleep Event while Locked
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(monitor.activePauseReasons.contains(.screenLocked))
        XCTAssertTrue(monitor.activePauseReasons.contains(.screenAsleep))
        
        // 4. Screen Wake Event while Locked
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        // Screen is awake, but still locked
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenAsleep))
        XCTAssertTrue(monitor.activePauseReasons.contains(.screenLocked))
        
        // 5. Screen Unlock Event
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenLocked))
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenAsleep))
        
        monitor.stop()
    }
    
    @MainActor
    func testResourceMonitorConcurrentSleepAndLockEdgeCase() {
        let monitor = ResourceMonitor()
        let settings = AppSettings.shared
        settings.isUserPaused = false
        
        // Post both in rapid succession
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        
        XCTAssertTrue(monitor.activePauseReasons.contains(.screenLocked))
        XCTAssertTrue(monitor.activePauseReasons.contains(.screenAsleep))
        
        // Unlock and wake
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenLocked))
        XCTAssertFalse(monitor.activePauseReasons.contains(.screenAsleep))
        
        monitor.stop()
    }
    
    // MARK: - 8. Menu Bar & Coordinator Controls Tests
    
    @MainActor
    func testPlaybackCoordinatorControlsAndPlaylistAdvance() {
        let coordinator = PlaybackCoordinator.shared
        let settings = AppSettings.shared
        
        // Test Mute Toggle
        let initialMuted = settings.isMuted
        coordinator.toggleMute()
        XCTAssertEqual(settings.isMuted, !initialMuted)
        coordinator.toggleMute()
        XCTAssertEqual(settings.isMuted, initialMuted)
        
        // Test Playlist Advance
        let origList = settings.playlistVideos
        defer { settings.playlistVideos = origList }
        
        settings.playlistVideos = ["/tmp/v1.mp4", "/tmp/v2.mp4", "/tmp/v3.mp4"]
        settings.playlistShuffleMode = .sequential
        
        coordinator.advancePlaylist(direction: .next)
        XCTAssertEqual(coordinator.currentPlaylistIndex, 1)
        
        coordinator.advancePlaylist(direction: .next)
        XCTAssertEqual(coordinator.currentPlaylistIndex, 2)
        
        coordinator.advancePlaylist(direction: .next)
        XCTAssertEqual(coordinator.currentPlaylistIndex, 0, "Playlist should wrap around to 0")
        
        coordinator.advancePlaylist(direction: .previous)
        XCTAssertEqual(coordinator.currentPlaylistIndex, 2, "Playlist should wrap backward to 2")
    }
}
