import AppKit
import AVFoundation
import Combine

@MainActor
public final class WindowManager: NSObject, MouseMotionTrackerDelegate {
    public static let shared = WindowManager()
    
    private var windowControllers: [CGDirectDisplayID: BackdropWindowController] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
        MouseMotionTracker.shared.delegate = self
        setupScreenNotifications()
        setupSettingsBindings()
    }
    
    public func start() {
        rebuildWindows()
        if AppSettings.shared.isMouseInteractionEnabled {
            MouseMotionTracker.shared.start()
        }
    }
    
    private func setupScreenNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func activeSpaceDidChange() {
        // When switching Spaces or invoking Mission Control ("Show all desktop and app"),
        // immediately rest parallax transforms to identity and sleep the displaylink.
        // This ensures zero CATransaction commits conflict with WindowServer's gesture animation.
        resetAllTransforms()
        MouseMotionTracker.shared.sleepDisplayLink()
    }
    
    private func setupSettingsBindings() {
        let settings = AppSettings.shared
        
        settings.$windowLevelMode
            .dropFirst()
            .sink { [weak self] levelMode in
                self?.updateWindowLevels(levelMode)
            }
            .store(in: &cancellables)
        
        settings.$videoGravity
            .dropFirst()
            .sink { [weak self] gravity in
                self?.updateVideoGravity(gravity)
            }
            .store(in: &cancellables)
        
        settings.$displayMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.reconnectPlayers()
            }
            .store(in: &cancellables)
            
        settings.$targetFPS
            .dropFirst()
            .sink { [weak self] fps in
                self?.updateFramerateMode(fps)
            }
            .store(in: &cancellables)
            
        Publishers.Merge4(
            settings.$dimmingAmount.dropFirst(),
            settings.$blurRadius.dropFirst(),
            settings.$saturationAmount.dropFirst(),
            settings.$contrastAmount.dropFirst()
        )
        .sink { [weak self] _ in
            self?.updateFilters()
        }
        .store(in: &cancellables)
        
        // Interactive Content Types (Web / Shaders / Particles)
        Publishers.Merge3(
            settings.$contentType.dropFirst().map { _ in () },
            settings.$selectedWebPreset.dropFirst().map { _ in () },
            settings.$webURLString.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.updateContentType()
        }
        .store(in: &cancellables)
        
        // Weather / Particle Overlays
        Publishers.Merge(
            settings.$isParticleOverlayEnabled.dropFirst().map { _ in () },
            settings.$particlePreset.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            self?.updateParticleOverlay()
        }
        .store(in: &cancellables)
        
        // Mouse Motion Interactivity
        Publishers.Merge4(
            settings.$isMouseInteractionEnabled.dropFirst().map { _ in () },
            settings.$parallaxIntensity.dropFirst().map { _ in () },
            settings.$parallaxTiltEnabled.dropFirst().map { _ in () },
            settings.$parallaxDepthLayers.dropFirst().map { _ in () }
        )
        .sink { [weak self] _ in
            if AppSettings.shared.isMouseInteractionEnabled {
                MouseMotionTracker.shared.start()
                MouseMotionTracker.shared.wakeDisplayLink()
            } else {
                MouseMotionTracker.shared.stop()
                self?.resetAllTransforms()
            }
        }
        .store(in: &cancellables)
    }
    
    @objc private func screenParametersChanged() {
        rebuildWindows()
        PlaybackCoordinator.shared.rebuildPerDisplayEngines()
    }
    
    public func rebuildWindows() {
        let currentScreens = NSScreen.screens
        let currentDisplayIDs = Set(currentScreens.compactMap { screen -> CGDirectDisplayID? in
            screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        })
        
        for (displayID, controller) in windowControllers {
            if !currentDisplayIDs.contains(displayID) {
                controller.tearDown()
                windowControllers.removeValue(forKey: displayID)
            }
        }
        
        let settings = AppSettings.shared
        for screen in currentScreens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            
            if let existingController = windowControllers[displayID] {
                existingController.updateScreenConfiguration(screen)
            } else {
                let controller = BackdropWindowController(
                    screen: screen,
                    levelMode: settings.windowLevelMode,
                    videoGravity: settings.videoGravity
                )
                controller.showBackdrop()
                windowControllers[displayID] = controller
            }
        }
        
        reconnectPlayers()
    }
    
    public func reconnectPlayers(coordinator: PlaybackCoordinator? = nil) {
        let coord = coordinator ?? PlaybackCoordinator.shared
        let primaryID = coord.primaryDisplayID
        let settings = AppSettings.shared
        
        for (displayID, controller) in windowControllers {
            if displayID == primaryID {
                controller.attachPlayer(coord.primaryEngine.player)
            } else if settings.displayMode == .perDisplay, let engine = coord.perDisplayEngines[displayID] {
                controller.attachPlayer(engine.player)
            } else {
                controller.attachPlayer(coord.primaryEngine.player)
            }
        }
    }
    
    public func freezeAllFrames() {
        for controller in windowControllers.values {
            controller.freezeCurrentFrame()
        }
    }
    
    public func unfreezeAllFrames() {
        for controller in windowControllers.values {
            controller.unfreezeCurrentFrame()
        }
    }
    
    // MARK: - Mouse Motion Delegate
    
    public func mouseMotionTrackerDidTick(globalLocation: CGPoint, dt: Double) -> Bool {
        var allResting = true
        for controller in windowControllers.values {
            let resting = controller.tickParallax(mouseLocation: globalLocation, dt: dt)
            if !resting {
                allResting = false
            }
        }
        return allResting
    }
    
    public func resetAllTransforms() {
        for controller in windowControllers.values {
            controller.resetTransforms()
        }
    }
    
    // MARK: - Controller Updates
    
    public func updateContentType() {
        for controller in windowControllers.values {
            controller.updateContentType()
        }
    }
    
    public func updateParticleOverlay() {
        for controller in windowControllers.values {
            controller.updateParticleOverlay()
        }
    }
    
    private func updateWindowLevels(_ mode: WindowLevelMode) {
        for controller in windowControllers.values {
            controller.updateWindowLevel(mode)
        }
    }
    
    private func updateVideoGravity(_ gravity: AVLayerVideoGravity) {
        for controller in windowControllers.values {
            controller.updateVideoGravity(gravity)
        }
    }
    
    private func updateFramerateMode(_ fps: TargetFPS) {
        for controller in windowControllers.values {
            controller.updateFramerateMode(fps)
        }
    }
    
    public func updateFilters() {
        for controller in windowControllers.values {
            controller.updateFilters()
        }
    }
    
    public func setDisplayLinkActive(_ active: Bool) {
        for controller in windowControllers.values {
            controller.setDisplayLinkActive(active)
        }
    }
    
    public func setWindowsVisible(_ visible: Bool) {
        for controller in windowControllers.values {
            controller.setWindowVisible(visible)
        }
    }
    
    public func pauseInteractiveLayers() {
        for controller in windowControllers.values {
            controller.pauseInteractiveLayers()
        }
    }
    
    public func resumeInteractiveLayers() {
        for controller in windowControllers.values {
            controller.resumeInteractiveLayers()
        }
    }
    
    public func tearDown() {
        MouseMotionTracker.shared.stop()
        for controller in windowControllers.values {
            controller.tearDown()
        }
        windowControllers.removeAll()
    }
}
