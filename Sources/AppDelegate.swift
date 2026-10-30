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
        
        menuController = StatusMenuController()
        menuController.delegate = self
        
        WindowManager.shared.start()
        PlaybackCoordinator.shared.start()
        
        setupRemoteCommands()
        
        NSLog("[LiveWallpaper] Launched successfully.")
    }
    
    private func setupRemoteCommands() {
        let center = DistributedNotificationCenter.default()
        
        center.addObserver(
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
        
        center.addObserver(
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
        
        center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.togglePlayPause"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PlaybackCoordinator.shared.togglePlayPause()
            }
        }
        
        center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.pause"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.isUserPaused = true
                PlaybackCoordinator.shared.resourceMonitor.evaluateAllConditions()
            }
        }
        
        center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.play"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppSettings.shared.isUserPaused = false
                PlaybackCoordinator.shared.resourceMonitor.evaluateAllConditions()
            }
        }
        
        center.addObserver(
            forName: NSNotification.Name("com.local.LiveWallpaper.openSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.openSettingsWindow()
            }
        }
    }
    
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppSettings.shared.contentType = .video
        PlaybackCoordinator.shared.loadVideo(url: url)
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("[LiveWallpaper] Terminating.")
        PlaybackCoordinator.shared.tearDown()
        WindowManager.shared.tearDown()
    }
    
    public func statusMenuDidRequestSettings() {
        openSettingsWindow()
    }
    
    public func openSettingsWindow() {
        if settingsWindowController == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "LiveWallpaper Settings"
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
