import AppKit
import SwiftUI
import Darwin

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, StatusMenuControllerDelegate, NSWindowDelegate {
    public static private(set) var shared: AppDelegate?
    
    private var menuController: StatusMenuController?
    private var settingsWindowController: NSWindowController?
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?
    private var remoteCommandObservers: [NSObjectProtocol] = []
    private var windowCloseObserver: NSObjectProtocol?
    private static var singleInstanceLockFD: Int32 = -1
    
    public override init() {
        super.init()
        Self.shared = self
    }
    
    private static func acquireSingleInstanceLock() -> Bool {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return true
        }
        let appDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let lockURL = appDir.appendingPathComponent("LiveWallpaper.lock")
        
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false // Another instance already holds the lock!
        }
        
        singleInstanceLockFD = fd
        return true
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Enforce Single-Instance: If another instance of LiveWallpaper is already running, activate it and exit immediately
        if !Self.acquireSingleInstanceLock() {
            AppLogger.general.info("Duplicate instance detected. Activating existing instance and exiting.")
            
            // Notify existing instance to bring its menu or settings to front
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.local.LiveWallpaper.openSettings"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            
            let alert = NSAlert()
            alert.messageText = "LiveWallpaper is Already Running"
            alert.informativeText = "LiveWallpaper is already running and active in your top menu bar (play icon). Multiple instances cannot run simultaneously."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
            exit(0)
        }
        
        // 2. Warn if user launched directly from a mounted disk image (.dmg) instead of /Applications
        if Bundle.main.bundlePath.hasPrefix("/Volumes/") {
            let alert = NSAlert()
            alert.messageText = "Install LiveWallpaper First"
            alert.informativeText = "You are currently running LiveWallpaper directly from the disk image installer. Please drag LiveWallpaper to your Applications folder first so your settings and screen saver remain permanently configured."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Applications Folder")
            alert.addButton(withTitle: "Continue Anyway")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                exit(0)
            }
        }
        
        NSApp.setActivationPolicy(.accessory)
        setupSignalHandlers()
        
        // Save original system desktop wallpapers
        LockScreenPosterManager.shared.saveOriginalWallpapers()
        
        // Menu bar UI is natively handled by SwiftUI MenuBarExtra in LiveWallpaperApp
        WindowManager.shared.start()
        PlaybackCoordinator.shared.start()
        
        setupRemoteCommands()
        
        AppLogger.general.info("Launched successfully.")
    }
    
    private func setupSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termSource.setEventHandler {
            NSApp.terminate(nil)
        }
        termSource.resume()
        self.sigtermSource = termSource
        
        signal(SIGINT, SIG_IGN)
        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler {
            NSApp.terminate(nil)
        }
        intSource.resume()
        self.sigintSource = intSource
    }
    
    private func setupRemoteCommands() {
        let center = DistributedNotificationCenter.default()
        
        let obs1 = center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.loadVideo"),
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                let path = (notification.userInfo?["path"] as? String) ?? UserDefaults.standard.string(forKey: "videoPath")
                if let p = path {
                    let url = URL(fileURLWithPath: p)
                    if FileManager.default.fileExists(atPath: url.path) {
                        AppSettings.shared.contentType = .video
                        PlaybackCoordinator.shared.loadVideo(url: url)
                        WindowManager.shared.updateContentType()
                    }
                }
            }
        }
        remoteCommandObservers.append(obs1)
        
        let obs2 = center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.setMode"),
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                if let type = notification.userInfo?["type"] as? String {
                    if type == "video" {
                        AppSettings.shared.contentType = .video
                    } else if type == "metal" {
                        AppSettings.shared.contentType = .metal
                        if let presetName = notification.userInfo?["preset"] as? String {
                            for p in MetalShaderPreset.allCases {
                                if p.rawValue.lowercased().contains(presetName.lowercased()) {
                                    AppSettings.shared.metalPreset = p
                                    break
                                }
                            }
                        }
                    } else if type == "web" {
                        AppSettings.shared.contentType = .web
                        if let preset = notification.userInfo?["preset"] as? String {
                            AppSettings.shared.selectedWebPreset = preset
                        }
                    } else if type == "particles" {
                        AppSettings.shared.contentType = .particles
                        if let presetName = notification.userInfo?["preset"] as? String {
                            for p in ParticlePreset.allCases {
                                if p.rawValue.lowercased().contains(presetName.lowercased()) {
                                    AppSettings.shared.particlePreset = p
                                    break
                                }
                            }
                        }
                    }
                    WindowManager.shared.updateContentType()
                }
            }
        }
        remoteCommandObservers.append(obs2)
        
        let obs3 = center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.togglePlayPause"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PlaybackCoordinator.shared.togglePlayPause()
            }
        }
        remoteCommandObservers.append(obs3)
        
        let obs4 = center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.pause"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.isUserPaused = true
                PlaybackCoordinator.shared.resourceMonitor.evaluateAllConditions()
            }
        }
        remoteCommandObservers.append(obs4)
        
        let obs5 = center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.play"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.isUserPaused = false
                PlaybackCoordinator.shared.resourceMonitor.evaluateAllConditions()
            }
        }
        remoteCommandObservers.append(obs5)
        
        let obs6 = center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.openSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.openSettingsWindow()
            }
        }
        remoteCommandObservers.append(obs6)
        
        setupWindowCloseObserver()
    }
    
    private func setupWindowCloseObserver() {
        if windowCloseObserver == nil {
            windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    self?.handleWindowWillClose(notification)
                }
            }
        }
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppSettings.shared.contentType = .video
        PlaybackCoordinator.shared.loadVideo(url: url)
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        AppLogger.general.info("Terminating: restoring static desktop wallpaper.")
        PlaybackCoordinator.shared.tearDown()
        WindowManager.shared.tearDown()
        
        // Restore original system wallpaper
        LockScreenPosterManager.shared.restoreOriginalWallpapers()
        
        for observer in remoteCommandObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        remoteCommandObservers.removeAll()
        
        if let closeObs = windowCloseObserver {
            NotificationCenter.default.removeObserver(closeObs)
            windowCloseObserver = nil
        }
        
        if Self.singleInstanceLockFD >= 0 {
            flock(Self.singleInstanceLockFD, LOCK_UN)
            close(Self.singleInstanceLockFD)
            Self.singleInstanceLockFD = -1
        }
    }
    
    public func statusMenuDidRequestSettings() {
        openSettingsWindow()
    }
    
    public func openSettingsWindow() {
        // Transition activation policy to regular so settings window receives focus and Dock icon appears while open
        NSApp.setActivationPolicy(.regular)
        
        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "LiveWallpaper Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            
            settingsWindowController = NSWindowController(window: window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    public var isSettingsWindowVisible: Bool {
        return settingsWindowController?.window?.isVisible == true
    }
    
    public func windowWillClose(_ notification: Notification) {
        handleWindowWillClose(notification)
    }
    
    private func handleWindowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, !(closedWindow is BackdropWindow) else {
            return
        }
        SystemDiagnostics.shared.stopMonitoring()
        
        DispatchQueue.main.async {
            let remainingUserWindows = NSApp.windows.filter { w in
                w !== closedWindow && w.isVisible && !(w is BackdropWindow) && w.className != "NSStatusBarWindow"
            }
            if remainingUserWindows.isEmpty {
                // Hide the Dock icon when all settings/main windows are closed
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    deinit {
        for observer in remoteCommandObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let closeObs = windowCloseObserver {
            NotificationCenter.default.removeObserver(closeObs)
        }
    }
}
