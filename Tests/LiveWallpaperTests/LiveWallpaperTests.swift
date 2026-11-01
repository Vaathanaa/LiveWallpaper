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
    
    // MARK: - 9. FileValidator Security Tests
    
    func testFileValidatorValidVideo() {
        let sampleURL = sampleVideoURL
        let result = FileValidator.validateVideoURL(sampleURL)
        switch result {
        case .success(let validatedURL):
            XCTAssertEqual(validatedURL.standardizedFileURL.path, sampleURL.standardizedFileURL.path)
        case .failure(let error):
            XCTFail("Expected valid video file to succeed, got error: \(error)")
        }
    }
    
    func testFileValidatorNonFileURL() {
        guard let remoteURL = URL(string: "https://example.com/video.mp4") else {
            XCTFail("Failed to construct remote URL")
            return
        }
        let result = FileValidator.validateVideoURL(remoteURL)
        switch result {
        case .success:
            XCTFail("Remote URL must be rejected by FileValidator")
        case .failure(let error):
            XCTAssertEqual(error, .notAFileURL)
        }
    }
    
    func testFileValidatorPathTraversal() {
        let traversalURL = URL(fileURLWithPath: "/System/Library/../etc/passwd")
        let result = FileValidator.validateVideoURL(traversalURL)
        switch result {
        case .success:
            XCTFail("Path traversal URL must be rejected by FileValidator")
        case .failure(let error):
            XCTAssertEqual(error, .pathTraversalAttempt)
        }
    }
    
    func testFileValidatorNonExistentFile() {
        let missingURL = URL(fileURLWithPath: "/tmp/non_existent_video_\(UUID().uuidString).mp4")
        let result = FileValidator.validateVideoURL(missingURL)
        switch result {
        case .success:
            XCTFail("Non-existent file must be rejected by FileValidator")
        case .failure(let error):
            XCTAssertEqual(error, .fileDoesNotExist)
        }
    }
    
    func testFileValidatorUnsupportedFileType() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let textFileURL = tempDir.appendingPathComponent("test_unsupported_\(UUID().uuidString).txt")
        try "Not a video file".write(to: textFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textFileURL) }
        
        let result = FileValidator.validateVideoURL(textFileURL)
        switch result {
        case .success:
            XCTFail("Text file must be rejected as unsupported file type")
        case .failure(let error):
            if case .unsupportedContentType = error {
                // Expected
            } else {
                XCTFail("Expected unsupportedContentType, got \(error)")
            }
        }
    }
    
    func testFileValidatorSymlinkRejection() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let symlinkURL = tempDir.appendingPathComponent("test_symlink_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: symlinkURL)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: sampleVideoURL)
        defer { try? FileManager.default.removeItem(at: symlinkURL) }
        
        let result = FileValidator.validateVideoURL(symlinkURL)
        switch result {
        case .success:
            XCTFail("Symlink must be rejected by FileValidator for security sandbox integrity")
        case .failure(let error):
            XCTAssertEqual(error, .isSymbolicLink)
        }
    }
    
    func testFileValidatorValidateFolder() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_folder_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let textFileURL = tempDir.appendingPathComponent("note.txt")
        try "Ignore me".write(to: textFileURL, atomically: true, encoding: .utf8)
        
        let videoCopyURL = tempDir.appendingPathComponent("valid_video.mp4")
        try FileManager.default.copyItem(at: sampleVideoURL, to: videoCopyURL)
        
        let validVideos = FileValidator.validateFolder(url: tempDir)
        XCTAssertEqual(validVideos.count, 1)
        XCTAssertEqual(validVideos.first?.lastPathComponent, "valid_video.mp4")
    }

    // MARK: - 10. SecurityBookmarkManager Ref-Counting & Lifecycle Tests
    
    func testSecurityBookmarkReferenceCountingLifecycle() {
        let sampleURL = sampleVideoURL
        SecurityBookmarkManager.shared.stopAccessingAll()
        XCTAssertEqual(SecurityBookmarkManager.shared.activeAccessCount(for: sampleURL), 0)
        
        guard let bookmarkData = SecurityBookmarkManager.shared.createBookmark(for: sampleURL) else {
            XCTFail("Bookmark creation failed")
            return
        }
        defer {
            SecurityBookmarkManager.shared.stopAccessingAll()
        }
        
        // Resolving bookmark increments reference count to 1
        guard let resolved = SecurityBookmarkManager.shared.resolveBookmark(bookmarkData) else {
            XCTFail("Failed to resolve bookmark")
            return
        }
        XCTAssertEqual(SecurityBookmarkManager.shared.activeAccessCount(for: resolved.url), 1)
        XCTAssertTrue(SecurityBookmarkManager.shared.activeURLs.contains(resolved.url))
        
        // Resolving again increments reference count to 2
        let resolved2 = SecurityBookmarkManager.shared.resolveBookmark(bookmarkData)
        XCTAssertNotNil(resolved2)
        XCTAssertEqual(SecurityBookmarkManager.shared.activeAccessCount(for: resolved.url), 2)
        
        // First stopAccessing decrements to 1
        SecurityBookmarkManager.shared.stopAccessing(url: resolved.url)
        XCTAssertEqual(SecurityBookmarkManager.shared.activeAccessCount(for: resolved.url), 1)
        XCTAssertTrue(SecurityBookmarkManager.shared.activeURLs.contains(resolved.url))
        
        // Second stopAccessing decrements to 0 and removes URL
        SecurityBookmarkManager.shared.stopAccessing(url: resolved.url)
        XCTAssertEqual(SecurityBookmarkManager.shared.activeAccessCount(for: resolved.url), 0)
        XCTAssertFalse(SecurityBookmarkManager.shared.activeURLs.contains(resolved.url))
    }

    // MARK: - 11. Multi-Display Window & Engine Reconnection Tests

    @MainActor
    func testWindowManagerRebuildWindowsSafety() {
        let wm = WindowManager.shared
        // Call rebuildWindows multiple times in succession to verify no dictionary mutation crash
        wm.rebuildWindows()
        wm.rebuildWindows()
        wm.rebuildWindows()
        XCTAssertFalse(wm.windowControllers.isEmpty)
    }

    @MainActor
    func testPlaybackCoordinatorVideoSwitchAndTeardownLifecycle() async {
        let coordinator = PlaybackCoordinator.shared
        let sampleURL = sampleVideoURL
        
        // Load video
        coordinator.loadVideo(url: sampleURL)
        
        // Await asynchronous engine pipeline setup
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.primaryEngine.videoURL, sampleURL)
        
        // Teardown and cleanup
        coordinator.tearDown()
        SecurityBookmarkManager.shared.stopAccessingAll()
        XCTAssertEqual(SecurityBookmarkManager.shared.activeAccessCount(for: sampleURL), 0)
    }

    // MARK: - 12. Day/Night Evaluation & Bookmark Stability Tests

    @MainActor
    func testDayNightEvaluationAccessCountStability() async {
        let coordinator = PlaybackCoordinator.shared
        let sampleURL = sampleVideoURL
        SecurityBookmarkManager.shared.stopAccessingAll()
        
        guard let bookmark = SecurityBookmarkManager.shared.createBookmark(for: sampleURL) else {
            XCTFail("Failed to create bookmark")
            return
        }
        
        let settings = AppSettings.shared
        let origDayNight = settings.isDayNightEnabled
        let origDayBm = settings.dayVideoBookmark
        let origNightBm = settings.nightVideoBookmark
        let origDayPath = settings.dayVideoPath
        let origNightPath = settings.nightVideoPath
        
        defer {
            settings.isDayNightEnabled = origDayNight
            settings.dayVideoBookmark = origDayBm
            settings.nightVideoBookmark = origNightBm
            settings.dayVideoPath = origDayPath
            settings.nightVideoPath = origNightPath
            coordinator.tearDown()
            SecurityBookmarkManager.shared.stopAccessingAll()
        }
        
        settings.isDayNightEnabled = true
        settings.dayVideoBookmark = bookmark
        settings.nightVideoBookmark = bookmark
        settings.dayVideoPath = sampleURL.path
        settings.nightVideoPath = sampleURL.path
        
        // Initial evaluation loads the video
        coordinator.evaluateDayNightMode()
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        let initialCount = SecurityBookmarkManager.shared.activeAccessCount(for: sampleURL)
        XCTAssertLessThanOrEqual(initialCount, 1)
        
        // Evaluate repeatedly - access count must remain balanced and not leak
        for _ in 0..<10 {
            coordinator.evaluateDayNightMode()
        }
        
        let subsequentCount = SecurityBookmarkManager.shared.activeAccessCount(for: sampleURL)
        XCTAssertEqual(subsequentCount, initialCount, "Repeated evaluateDayNightMode() must not leak security bookmark access tokens")
    }

    // MARK: - 13. Display Sleep & Audio Configuration Tests

    @MainActor
    func testVideoEnginePreventsDisplaySleepIsDisabled() {
        let engine = VideoEngine()
        XCTAssertFalse(
            engine.player.preventsDisplaySleepDuringVideoPlayback,
            "VideoEngine player must have preventsDisplaySleepDuringVideoPlayback == false to permit macOS idle display sleep"
        )
        engine.tearDown()
    }

    @MainActor
    func testVideoEngineAudioTrackMutingBehavior() async {
        let engine = VideoEngine()
        let sampleURL = sampleVideoURL
        
        await engine.loadVideo(url: sampleURL, targetFPS: .fps60, isMuted: true)
        XCTAssertTrue(engine.player.isMuted)
        XCTAssertEqual(engine.player.volume, 0.0)
        
        // Verify audio configuration application
        if let currentItem = engine.player.currentItem {
            for track in currentItem.tracks where track.assetTrack?.mediaType == .audio {
                XCTAssertFalse(track.isEnabled, "Audio tracks must be disabled when isMuted is true")
            }
        }
        
        engine.tearDown()
        SecurityBookmarkManager.shared.stopAccessingAll()
    }

    // MARK: - 14. Advanced Path Traversal Security Tests

    func testFileValidatorRejectsPercentEncodedTraversal() {
        let dangerousPaths = [
            "file:///Users/Shared/%2e%2e/test.mp4",
            "file:///Users/Shared/%2e%2e/%2e%2e/etc/passwd.mp4",
            "file:///Users/Shared/video%2f..%2fevil.mp4",
            "file:///Users/Shared/sub/..%2f../secret.mp4",
            "file:///Users/Shared/../root.mp4"
        ]
        
        for pathString in dangerousPaths {
            if let dangerousURL = URL(string: pathString) {
                let result = FileValidator.validateVideoURL(dangerousURL)
                switch result {
                case .success:
                    XCTFail("FileValidator failed to reject path traversal: \(pathString)")
                case .failure(let error):
                    XCTAssertEqual(error, .pathTraversalAttempt, "Expected pathTraversalAttempt for \(pathString), got \(error)")
                }
            }
        }
    }

    // MARK: - 15. Multi-Display Engine Bookmark Balancing Tests

    @MainActor
    func testMultiDisplayEngineBookmarkBalancing() async {
        let coordinator = PlaybackCoordinator.shared
        let sampleURL = sampleVideoURL
        SecurityBookmarkManager.shared.stopAccessingAll()
        
        guard let bookmark = SecurityBookmarkManager.shared.createBookmark(for: sampleURL) else {
            XCTFail("Failed to create bookmark")
            return
        }
        
        let settings = AppSettings.shared
        let origDisplayMode = settings.displayMode
        let origPerDisplayBm = settings.perDisplayVideoBookmarks
        let origPerDisplayPaths = settings.perDisplayVideoPaths
        
        defer {
            settings.displayMode = origDisplayMode
            settings.perDisplayVideoBookmarks = origPerDisplayBm
            settings.perDisplayVideoPaths = origPerDisplayPaths
            coordinator.tearDown()
            SecurityBookmarkManager.shared.stopAccessingAll()
        }
        
        settings.displayMode = .perDisplay
        let displayKey = "99999" // simulated non-primary display key
        settings.perDisplayVideoPaths = [displayKey: sampleURL.path]
        settings.perDisplayVideoBookmarks = [displayKey: bookmark]
        
        // Call updateSecondaryEngines repeatedly
        await coordinator.updateSecondaryEngines(url: sampleURL)
        let countAfterFirst = SecurityBookmarkManager.shared.activeAccessCount(for: sampleURL)
        
        await coordinator.updateSecondaryEngines(url: sampleURL)
        await coordinator.updateSecondaryEngines(url: sampleURL)
        let countAfterRepeated = SecurityBookmarkManager.shared.activeAccessCount(for: sampleURL)
        
        XCTAssertEqual(countAfterFirst, countAfterRepeated, "Repeated updateSecondaryEngines must not accumulate bookmark access tokens")
    }
}
