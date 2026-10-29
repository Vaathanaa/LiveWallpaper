import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, StatusMenuControllerDelegate {
    public static private(set) var shared: AppDelegate!
    
    private var menuController: StatusMenuController!
    private var settingsWindowController: NSWindowController?
    
    public override init() {
        super.init()
        Self.shared = self
    }
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Save original system desktop wallpapers
        LockScreenPosterManager.shared.saveOriginalWallpapers()
        
        menuController = StatusMenuController()
        menuController.delegate = self
        
        WindowManager.shared.start()
        PlaybackCoordinator.shared.start()
        
        setupRemoteCommands()
        
        NSLog("[VideoBackdrop] Launched successfully.")
    }
    
    private func setupRemoteCommands() {
        let center = DistributedNotificationCenter.default()
        
        center.addObserver(
            forName: NSNotification.Name("com.local.VideoBackdrop.loadVideo"),
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
        
        center.addObserver(
            forName: NSNotification.Name("com.local.VideoBackdrop.setMode"),
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                if let type = notification.userInfo?["type"] as? String {
                    if type == "video" {
                        AppSettings.shared.contentType = .video
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
        
        center.addObserver(
            forName: NSNotification.Name("com.local.VideoBackdrop.togglePlayPause"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PlaybackCoordinator.shared.togglePlayPause()
            }
        }
        
        center.addObserver(
            forName: NSNotification.Name("com.local.VideoBackdrop.pause"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.isUserPaused = true
                PlaybackCoordinator.shared.resourceMonitor.evaluateAllConditions()
            }
        }
        
        center.addObserver(
            forName: NSNotification.Name("com.local.VideoBackdrop.play"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.isUserPaused = false
                PlaybackCoordinator.shared.resourceMonitor.evaluateAllConditions()
            }
        }
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppSettings.shared.contentType = .video
        PlaybackCoordinator.shared.loadVideo(url: url)
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("[VideoBackdrop] Terminating: restoring static desktop wallpaper.")
        PlaybackCoordinator.shared.tearDown()
        WindowManager.shared.tearDown()
        
        // Restore original system wallpaper
        LockScreenPosterManager.shared.restoreOriginalWallpapers()
    }
    
    public func statusMenuDidRequestSettings() {
        openSettingsWindow()
    }
    
    public func openSettingsWindow() {
        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "VideoBackdrop Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            
            settingsWindowController = NSWindowController(window: window)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}
