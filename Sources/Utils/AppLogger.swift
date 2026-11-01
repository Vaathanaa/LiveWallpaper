import Foundation
import OSLog

public enum AppLogger {
    public static let general = Logger(subsystem: "com.local.LiveWallpaper", category: "General")
    public static let playback = Logger(subsystem: "com.local.LiveWallpaper", category: "Playback")
    public static let video = Logger(subsystem: "com.local.LiveWallpaper", category: "VideoEngine")
    public static let window = Logger(subsystem: "com.local.LiveWallpaper", category: "Window")
    public static let security = Logger(subsystem: "com.local.LiveWallpaper", category: "Security")
    public static let poster = Logger(subsystem: "com.local.LiveWallpaper", category: "Poster")
}
