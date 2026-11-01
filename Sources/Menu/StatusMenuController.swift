import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public protocol StatusMenuControllerDelegate: AnyObject {
    func statusMenuDidRequestSettings()
}

@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    public weak var delegate: StatusMenuControllerDelegate?
    public static var isMenuOpen: Bool = false
    
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    
    private let miniPlayerItem = NSMenuItem()
    private let statusHeaderItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
    private let playPauseItem = NSMenuItem(title: "Play", action: #selector(togglePlayPause), keyEquivalent: "p")
    private let nextPlaylistItem = NSMenuItem(title: "Next Wallpaper in Playlist", action: #selector(nextPlaylistItemClicked), keyEquivalent: "]")
    private let prevPlaylistItem = NSMenuItem(title: "Previous Wallpaper in Playlist", action: #selector(prevPlaylistItemClicked), keyEquivalent: "[")
    
    private let chooseVideoItem = NSMenuItem(title: "Choose Video...", action: #selector(chooseVideo), keyEquivalent: "o")
    private let muteItem = NSMenuItem(title: "Mute Audio", action: #selector(toggleMute), keyEquivalent: "m")
    
    // Interactive & Shader Controls
    private let contentTypeItem = NSMenuItem(title: "Wallpaper Type", action: nil, keyEquivalent: "")
    private let contentTypeMenu = NSMenu()
    
    private let weatherOverlayItem = NSMenuItem(title: "Weather Particle Overlay", action: nil, keyEquivalent: "")
    private let weatherOverlayMenu = NSMenu()
    
    private let parallaxToggleItem = NSMenuItem(title: "3D Mouse Parallax & Depth", action: #selector(toggleParallax), keyEquivalent: "")
    
    private let playbackSpeedItem = NSMenuItem(title: "Playback Speed", action: nil, keyEquivalent: "")
    private let playbackSpeedMenu = NSMenu()
    
    private let framerateItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
    private let framerateMenu = NSMenu()
    private let adaptiveFramerateItem = NSMenuItem(title: "⚡ Smart Adaptive (MagSafe 120Hz / Battery 60/24Hz)", action: #selector(toggleAdaptiveFramerate), keyEquivalent: "")
    
    private let displayModeItem = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
    private let displayModeMenu = NSMenu()
    
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Quit LiveWallpaper", action: #selector(quitApp), keyEquivalent: "q")
    
    private let speedOptions: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    public override init() {
        super.init()
        setupStatusItem()
        buildMenu()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let image = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: "LiveWallpaper")?
                .withSymbolConfiguration(symbolConfig) {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageOnly
            button.toolTip = "LiveWallpaper — Ultra-Smooth Live Desktop"
        }
        statusItem.menu = menu
        menu.delegate = self
    }
    
    private func buildMenu() {
        menu.removeAllItems()
        
        // Live Mini-Player Card with animated preview & scrubber
        let hosting = NSHostingView(rootView: MiniPlayerCardView())
        hosting.frame = NSRect(x: 0, y: 0, width: 294, height: 236)
        miniPlayerItem.view = hosting
        menu.addItem(miniPlayerItem)
        menu.addItem(NSMenuItem.separator())
        
        statusHeaderItem.isEnabled = false
        menu.addItem(statusHeaderItem)
        menu.addItem(NSMenuItem.separator())
        
        playPauseItem.target = self
        menu.addItem(playPauseItem)
        
        nextPlaylistItem.target = self
        menu.addItem(nextPlaylistItem)
        
        prevPlaylistItem.target = self
        menu.addItem(prevPlaylistItem)
        
        menu.addItem(NSMenuItem.separator())
        
        chooseVideoItem.target = self
        menu.addItem(chooseVideoItem)
        
        muteItem.target = self
        menu.addItem(muteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Wallpaper Types (Video / Web / Particles)
        buildContentTypeSubmenu()
        contentTypeItem.submenu = contentTypeMenu
        menu.addItem(contentTypeItem)
        
        // Weather Overlays
        buildWeatherOverlaySubmenu()
        weatherOverlayItem.submenu = weatherOverlayMenu
        menu.addItem(weatherOverlayItem)
        
        parallaxToggleItem.target = self
        menu.addItem(parallaxToggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        buildPlaybackSpeedSubmenu()
        playbackSpeedItem.submenu = playbackSpeedMenu
        menu.addItem(playbackSpeedItem)
        
        buildFramerateSubmenu()
        framerateItem.submenu = framerateMenu
        menu.addItem(framerateItem)
        
        buildDisplayModeSubmenu()
        displayModeItem.submenu = displayModeMenu
        menu.addItem(displayModeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        
        let screenSaverItem = NSMenuItem(title: "Preview Screen Saver", action: #selector(previewScreenSaver), keyEquivalent: "")
        screenSaverItem.target = self
        menu.addItem(screenSaverItem)
        
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    // MARK: - Content Type & Shaders Submenu
    
    private func buildContentTypeSubmenu() {
        contentTypeMenu.removeAllItems()
        let settings = AppSettings.shared
        
        let videoItem = NSMenuItem(title: "Video File (.mp4, .mov)", action: #selector(selectContentTypeVideo), keyEquivalent: "")
        videoItem.target = self
        videoItem.state = (settings.contentType == .video) ? .on : .off
        contentTypeMenu.addItem(videoItem)
        
        let metalHeader = NSMenuItem(title: "Native Metal 4 Compute Shaders (<15MB RAM):", action: nil, keyEquivalent: "")
        metalHeader.isEnabled = false
        contentTypeMenu.addItem(metalHeader)
        
        for preset in MetalShaderPreset.allCases {
            let item = NSMenuItem(title: "  \(preset.rawValue)", action: #selector(selectMetalPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = (settings.contentType == .metal && settings.metalPreset == preset) ? .on : .off
            contentTypeMenu.addItem(item)
        }
        
        let webHeader = NSMenuItem(title: "Web / Shaders (WebKit):", action: nil, keyEquivalent: "")
        webHeader.isEnabled = false
        contentTypeMenu.addItem(webHeader)
        
        let presets = [
            "Cyberpunk Matrix Rain": "Cyberpunk Matrix",
            "Deep Space Nebula": "Deep Space Nebula",
            "Interactive Particle Network": "Particle Network",
            "Minimal Aesthetic Clock": "Minimal Clock"
        ]
        for (label, key) in presets {
            let item = NSMenuItem(title: "  \(label)", action: #selector(selectWebPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = (settings.contentType == .web && settings.selectedWebPreset == key) ? .on : .off
            contentTypeMenu.addItem(item)
        }
        
        let particlesHeader = NSMenuItem(title: "Procedural Particles (Standalone):", action: nil, keyEquivalent: "")
        particlesHeader.isEnabled = false
        contentTypeMenu.addItem(particlesHeader)
        
        for preset in ParticlePreset.allCases where preset != .none {
            let item = NSMenuItem(title: "  \(preset.rawValue)", action: #selector(selectParticleStandalone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = (settings.contentType == .particles && settings.particlePreset == preset) ? .on : .off
            contentTypeMenu.addItem(item)
        }
    }
    
    // MARK: - Weather Particle Overlay Submenu
    
    private func buildWeatherOverlaySubmenu() {
        weatherOverlayMenu.removeAllItems()
        let settings = AppSettings.shared
        
        let toggleItem = NSMenuItem(
            title: settings.isParticleOverlayEnabled ? "Disable Overlay" : "Enable Weather Overlay",
            action: #selector(toggleWeatherOverlay),
            keyEquivalent: ""
        )
        toggleItem.target = self
        weatherOverlayMenu.addItem(toggleItem)
        weatherOverlayMenu.addItem(NSMenuItem.separator())
        
        for preset in ParticlePreset.allCases where preset != .none {
            let item = NSMenuItem(title: preset.rawValue, action: #selector(selectWeatherPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            item.state = (settings.isParticleOverlayEnabled && settings.particlePreset == preset) ? .on : .off
            weatherOverlayMenu.addItem(item)
        }
    }
    
    private func buildPlaybackSpeedSubmenu() {
        playbackSpeedMenu.removeAllItems()
        for speed in speedOptions {
            let label: String
            if speed == 1.0 {
                label = "1.0x (Normal Speed)"
            } else if speed < 1.0 {
                label = String(format: "%.2fx (Cinematic Slow-Mo)", speed)
            } else {
                label = String(format: "%.2fx", speed)
            }
            let item = NSMenuItem(title: label, action: #selector(selectPlaybackSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed
            playbackSpeedMenu.addItem(item)
        }
    }
    
    private func buildFramerateSubmenu() {
        framerateMenu.removeAllItems()
        
        adaptiveFramerateItem.target = self
        framerateMenu.addItem(adaptiveFramerateItem)
        framerateMenu.addItem(NSMenuItem.separator())
        
        for fps in TargetFPS.allCases {
            let item = NSMenuItem(title: fps.title, action: #selector(selectFramerate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = fps
            framerateMenu.addItem(item)
        }
    }
    
    private func buildDisplayModeSubmenu() {
        displayModeMenu.removeAllItems()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            displayModeMenu.addItem(item)
        }
        
        let settings = AppSettings.shared
        if settings.displayMode == .perDisplay {
            displayModeMenu.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: "Assign Display Wallpapers:", action: nil, keyEquivalent: "")
            header.isEnabled = false
            displayModeMenu.addItem(header)
            
            for screen in NSScreen.screens {
                if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                    let screenName = screen.localizedName
                    let key = String(displayID)
                    let currentVideo = settings.perDisplayVideoPaths[key].flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "Default Wallpaper"
                    let item = NSMenuItem(title: "\(screenName) (\(currentVideo))...", action: #selector(selectVideoForSpecificDisplay(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = displayID
                    displayModeMenu.addItem(item)
                }
            }
        }
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        Self.isMenuOpen = true
        buildContentTypeSubmenu()
        buildWeatherOverlaySubmenu()
        buildDisplayModeSubmenu()
        updateMenuState()
        AppSettings.shared.refreshLaunchAtLoginStatus()
    }
    
    public func menuDidClose(_ menu: NSMenu) {
        Self.isMenuOpen = false
    }
    
    public func updateMenuState() {
        let settings = AppSettings.shared
        let coordinator = PlaybackCoordinator.shared
        
        let isPlaylistActive = settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty
        nextPlaylistItem.isHidden = !isPlaylistActive
        prevPlaylistItem.isHidden = !isPlaylistActive
        
        if settings.contentType == .web {
            statusHeaderItem.title = "Web Shader: \(settings.selectedWebPreset)"
        } else if settings.contentType == .particles {
            statusHeaderItem.title = "Particles: \(settings.particlePreset.rawValue)"
        } else if coordinator.primaryEngine.videoURL == nil {
            statusHeaderItem.title = "No Video Selected"
        } else if !coordinator.resourceMonitor.activePauseReasons.isEmpty {
            let reason = coordinator.resourceMonitor.activePauseReasons.first?.description ?? "Paused"
            statusHeaderItem.title = "Paused: \(reason)"
        } else {
            var details: [String] = []
            if settings.isAdaptiveFramerateEnabled {
                let pwr = ResourceMonitor.isOnBatteryPower() ? "Battery" : "AC"
                details.append("Adaptive \(settings.targetFPS.shortTitle) (\(pwr))")
            } else {
                details.append(settings.targetFPS.shortTitle)
            }
            if settings.playbackSpeed != 1.0 {
                details.append(String(format: "%.2fx", settings.playbackSpeed))
            }
            if settings.isDayNightEnabled {
                details.append(ResourceMonitor.isDarkMode() ? "Night" : "Day")
            }
            if isPlaylistActive {
                details.append("Playlist #\(coordinator.currentPlaylistIndex + 1)/\(settings.playlistVideos.count)")
            }
            statusHeaderItem.title = "Playing (\(details.joined(separator: ", ")))"
        }
        
        playPauseItem.title = coordinator.primaryEngine.isPlaying ? "Pause" : "Play"
        muteItem.state = settings.isMuted ? .on : .off
        parallaxToggleItem.state = settings.isMouseInteractionEnabled ? .on : .off
        
        adaptiveFramerateItem.state = settings.isAdaptiveFramerateEnabled ? .on : .off
        for item in framerateMenu.items {
            if let fps = item.representedObject as? TargetFPS {
                item.state = (!settings.isAdaptiveFramerateEnabled && fps == settings.targetFPS) ? .on : .off
            }
        }
        
        for item in playbackSpeedMenu.items {
            if let speed = item.representedObject as? Double {
                item.state = (abs(speed - settings.playbackSpeed) < 0.01) ? .on : .off
            }
        }
        
        for item in displayModeMenu.items {
            if let mode = item.representedObject as? DisplayMode {
                item.state = (mode == settings.displayMode) ? .on : .off
            }
        }
        
        launchAtLoginItem.state = settings.isLaunchAtLoginEnabled ? .on : .off
    }
    
    // MARK: - Action Selectors
    
    @objc private func selectContentTypeVideo() {
        AppSettings.shared.contentType = .video
        updateMenuState()
        WindowManager.shared.updateContentType()
    }
    
    @objc private func selectMetalPreset(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? MetalShaderPreset {
            AppSettings.shared.metalPreset = preset
            AppSettings.shared.contentType = .metal
            updateMenuState()
            WindowManager.shared.updateContentType()
        }
    }
    
    @objc private func selectWebPreset(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? String {
            AppSettings.shared.selectedWebPreset = preset
            AppSettings.shared.webURLString = nil
            AppSettings.shared.contentType = .web
            updateMenuState()
            WindowManager.shared.updateContentType()
        }
    }
    
    @objc private func selectParticleStandalone(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? ParticlePreset {
            AppSettings.shared.particlePreset = preset
            AppSettings.shared.contentType = .particles
            updateMenuState()
            WindowManager.shared.updateContentType()
        }
    }
    
    @objc private func toggleWeatherOverlay() {
        AppSettings.shared.isParticleOverlayEnabled.toggle()
        updateMenuState()
        WindowManager.shared.updateParticleOverlay()
    }
    
    @objc private func selectWeatherPreset(_ sender: NSMenuItem) {
        if let preset = sender.representedObject as? ParticlePreset {
            AppSettings.shared.particlePreset = preset
            AppSettings.shared.isParticleOverlayEnabled = true
            updateMenuState()
            WindowManager.shared.updateParticleOverlay()
        }
    }
    
    @objc private func toggleParallax() {
        AppSettings.shared.isMouseInteractionEnabled.toggle()
        updateMenuState()
    }
    
    @objc private func togglePlayPause() {
        PlaybackCoordinator.shared.togglePlayPause()
        updateMenuState()
    }
    
    @objc private func nextPlaylistItemClicked() {
        PlaybackCoordinator.shared.advancePlaylist(direction: .next)
        updateMenuState()
    }
    
    @objc private func prevPlaylistItemClicked() {
        PlaybackCoordinator.shared.advancePlaylist(direction: .previous)
        updateMenuState()
    }
    
    @objc private func toggleMute() {
        PlaybackCoordinator.shared.toggleMute()
        updateMenuState()
    }
    
    @objc private func selectPlaybackSpeed(_ sender: NSMenuItem) {
        if let speed = sender.representedObject as? Double {
            PlaybackCoordinator.shared.setPlaybackSpeed(speed)
            updateMenuState()
        }
    }
    
    @objc private func toggleAdaptiveFramerate() {
        AppSettings.shared.isAdaptiveFramerateEnabled.toggle()
        PlaybackCoordinator.shared.evaluateAdaptiveFramerate()
        updateMenuState()
    }
    
    @objc private func selectFramerate(_ sender: NSMenuItem) {
        if let fps = sender.representedObject as? TargetFPS {
            AppSettings.shared.isAdaptiveFramerateEnabled = false
            PlaybackCoordinator.shared.setFramerate(fps)
            updateMenuState()
        }
    }
    
    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? DisplayMode {
            AppSettings.shared.displayMode = mode
            buildDisplayModeSubmenu()
            updateMenuState()
        }
    }
    
    @objc private func selectVideoForSpecificDisplay(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? CGDirectDisplayID else { return }
        
        // Close menu first so the NSOpenPanel can present properly in LSUIElement apps
        menu.cancelTracking()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
            if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
            if let mp4 = UTType(filenameExtension: "mp4") { types.append(mp4) }
            panel.allowedContentTypes = types
            panel.prompt = "Assign to Display"
            panel.message = "Choose a video backdrop for this display:"
            panel.level = .floating
            panel.center()
            
            NSApp.activate(ignoringOtherApps: true)
            
            if panel.runModal() == .OK, let url = panel.url {
                PlaybackCoordinator.shared.setVideoForDisplay(url: url, displayID: displayID)
                self?.buildDisplayModeSubmenu()
                self?.updateMenuState()
            }
        }
    }
    
    @objc private func toggleLaunchAtLogin() {
        let current = AppSettings.shared.isLaunchAtLoginEnabled
        AppSettings.shared.setLaunchAtLogin(!current)
        launchAtLoginItem.state = !current ? .on : .off
    }
    
    @objc private func chooseVideo() {
        // Close the menu bar dropdown FIRST — NSOpenPanel.runModal() cannot present
        // while an NSMenu event-tracking run loop is active (LSUIElement app).
        // Dispatch after a short delay so the menu fully dismisses before the
        // modal sheet steals first-responder focus.
        menu.cancelTracking()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
            if let m4v = UTType(filenameExtension: "m4v") { types.append(m4v) }
            if let mp4 = UTType(filenameExtension: "mp4") { types.append(mp4) }
            panel.allowedContentTypes = types
            panel.prompt = "Set as Backdrop"
            panel.message = "Choose a video file (.mp4, .mov, .m4v) for your desktop backdrop:"
            panel.level = .floating
            panel.center()
            
            NSApp.activate(ignoringOtherApps: true)
            
            if panel.runModal() == .OK, let url = panel.url {
                AppSettings.shared.contentType = .video
                PlaybackCoordinator.shared.loadVideo(url: url)
                self?.updateMenuState()
            }
        }
    }
    
    @objc private func previewScreenSaver() {
        menu.cancelTracking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let script = """
            tell application "System Events"
                set current screen saver to screen saver "LiveWallpaper"
                start current screen saver
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
            }
        }
    }
    
    @objc private func openSettings() {
        delegate?.statusMenuDidRequestSettings()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
