import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct MenuBarView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var coordinator = PlaybackCoordinator.shared
    
    public init() {}
    
    public var body: some View {
        VStack {
            // Play / Pause Quick Control
            Button(action: {
                coordinator.togglePlayPause()
            }) {
                Label(coordinator.isPlaying ? "Pause Wallpaper" : "Play Wallpaper",
                      systemImage: coordinator.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut("p", modifiers: .command)
            
            // Select Video File
            Button(action: {
                chooseVideo()
            }) {
                Label("Select Video...", systemImage: "folder.fill")
            }
            .keyboardShortcut("o", modifiers: .command)
            
            // Audio Mute Quick Toggle
            Button(action: {
                coordinator.toggleMute()
            }) {
                Label(settings.isMuted ? "Unmute Audio" : "Mute Audio",
                      systemImage: settings.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .keyboardShortcut("m", modifiers: .command)
            
            // Playlist quick advance if playlist enabled
            if settings.isPlaylistEnabled && !settings.playlistVideos.isEmpty {
                Divider()
                Button(action: {
                    coordinator.advancePlaylist(direction: .next)
                }) {
                    Label("Next in Playlist", systemImage: "forward.end.fill")
                }
                .keyboardShortcut("]", modifiers: .command)
                
                Button(action: {
                    coordinator.advancePlaylist(direction: .previous)
                }) {
                    Label("Previous in Playlist", systemImage: "backward.end.fill")
                }
                .keyboardShortcut("[", modifiers: .command)
            }
            
            Divider()
            
            // Launch at Login via SMAppService.mainApp
            Toggle("Launch at Login", isOn: Binding(
                get: { settings.isLaunchAtLoginEnabled },
                set: { settings.setLaunchAtLogin($0) }
            ))
            
            // Settings Window
            Button(action: {
                AppDelegate.shared?.openSettingsWindow()
            }) {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            // Quit
            Button(role: .destructive, action: {
                NSApp.terminate(nil)
            }) {
                Label("Quit LiveWallpaper", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            settings.refreshLaunchAtLoginStatus()
        }
    }
    
    private func chooseVideo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
            
            let previousPolicy = NSApp.activationPolicy()
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
            
            let response = panel.runModal()
            if previousPolicy != .regular && AppDelegate.shared?.isSettingsWindowVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
            
            if response == .OK, let url = panel.url {
                if case .success(let validURL) = FileValidator.validateVideoURL(url) {
                    AppSettings.shared.contentType = .video
                    PlaybackCoordinator.shared.loadVideo(url: validURL)
                }
            }
        }
    }
}
