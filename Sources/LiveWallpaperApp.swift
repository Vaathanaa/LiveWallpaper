import SwiftUI

@main
struct LiveWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("LiveWallpaper", systemImage: "play.desktopcomputer") {
            MenuBarView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
