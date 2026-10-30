import AppKit
import AVFoundation

@MainActor
public final class LockScreenPosterManager {
    public static let shared = LockScreenPosterManager()
    
    private let defaults = UserDefaults.standard
    private var originalWallpapers: [CGDirectDisplayID: URL] = [:]
    public var posterURL: URL?
    
    private init() {
        saveOriginalWallpapers()
    }
    
    public func saveOriginalWallpapers() {
        // Backup system Index.plist once so we can perfectly restore macOS default on quit
        Self.backupIndexPlistOnce()
        
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                if !url.path.contains("poster_") && !url.path.contains("lockscreen_poster") && !url.path.contains("lockscreen.png") && !url.path.contains("LiveWallpaper") && !url.path.contains("VideoBackdrop") {
                    originalWallpapers[id] = url
                    defaults.set(url.path, forKey: "originalWallpaper_\(id)")
                }
            }
        }
    }
    
    private nonisolated static func backupIndexPlistOnce() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let storeDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("Index.plist")
        let backupURL = storeDir.appendingPathComponent("Index.plist.backup")
        
        if FileManager.default.fileExists(atPath: indexURL.path) && !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: indexURL, to: backupURL)
            NSLog("[LockScreenPosterManager] Created system wallpaper Index.plist.backup")
        }
    }
    
    public func updateLockScreenPoster(for asset: AVAsset, at time: CMTime = .zero) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let liveWallpaperDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        let videoBackdropDir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let moviesDir = home.appendingPathComponent("Movies/LiveWallpaper", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: liveWallpaperDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videoBackdropDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: moviesDir, withIntermediateDirectories: true)
        
        let stableURL = liveWallpaperDir.appendingPathComponent("lockscreen_poster.jpg")
        let backupStableURL = videoBackdropDir.appendingPathComponent("lockscreen_poster.jpg")
        let moviesPosterURL = moviesDir.appendingPathComponent("lockscreen_poster.jpg")
        
        Task.detached(priority: .userInitiated) {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 3840, height: 2160)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            
            var targetTime = time
            if targetTime <= .zero {
                if let duration = try? await asset.load(.duration), CMTimeGetSeconds(duration) > 2.0 {
                    targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                }
            }
            
            do {
                let (cgImage, _) = try await gen.image(at: targetTime)
                let rep = NSBitmapImageRep(cgImage: cgImage)
                
                // 1. Write high-quality JPEG poster for Application Support & Movies
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    try? jpegData.write(to: stableURL, options: .atomic)
                    try? jpegData.write(to: backupStableURL, options: .atomic)
                    try? jpegData.write(to: moviesPosterURL, options: .atomic)
                }
                
                // 2. CRITICAL for macOS Lock Screen: Write directly to /Library/Caches/Desktop Pictures/<user-uuid>/lockscreen.png
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    let systemCacheDir = "/Library/Caches/Desktop Pictures"
                    if let items = try? FileManager.default.contentsOfDirectory(atPath: systemCacheDir) {
                        for item in items {
                            let userDir = (systemCacheDir as NSString).appendingPathComponent(item)
                            var isDir: ObjCBool = false
                            if FileManager.default.fileExists(atPath: userDir, isDirectory: &isDir), isDir.boolValue {
                                let lockscreenPNG = (userDir as NSString).appendingPathComponent("lockscreen.png")
                                try? pngData.write(to: URL(fileURLWithPath: lockscreenPNG), options: .atomic)
                                NSLog("[LockScreenPosterManager] Successfully updated system lockscreen.png at: %@", lockscreenPNG)
                            }
                        }
                    }
                }
                
                // 3. Set desktop image via NSWorkspace
                await MainActor.run {
                    let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                        .allowClipping: true,
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue
                    ]
                    
                    for screen in NSScreen.screens {
                        do {
                            try NSWorkspace.shared.setDesktopImageURL(stableURL, for: screen, options: options)
                        } catch {
                            NSLog("[LockScreenPosterManager] Warning setting desktop image: \(error.localizedDescription)")
                        }
                    }
                    
                    LockScreenPosterManager.shared.posterURL = stableURL
                }
                
                // 4. Update Index.plist for Desktop choices with individual space/display mode
                Self.updateIndexPlistForDesktop(stableURL: stableURL)
                
                // 5. Asynchronously notify System Events on background utility queue
                DispatchQueue.global(qos: .utility).async {
                    let pathString = stableURL.path.replacingOccurrences(of: "\"", with: "\\\"")
                    let script = """
                    tell application "System Events"
                        set posterPath to POSIX file "\(pathString)"
                        repeat with d in desktops
                            set picture of d to posterPath
                        end repeat
                    end tell
                    """
                    if let appleScript = NSAppleScript(source: script) {
                        var err: NSDictionary?
                        appleScript.executeAndReturnError(&err)
                    }
                }
            } catch {
                NSLog("[LockScreenPosterManager] Error extracting frame: \(error.localizedDescription)")
            }
        }
    }
    
    /// Synchronizes the active video directly to macOS's native 120Hz Screen Saver and caches
    public func syncScreenSaverVideo(from sourceURL: URL, asset: AVAsset) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let liveWallpaperDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        let videoBackdropDir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        
        let localVideo1 = liveWallpaperDir.appendingPathComponent("current_wallpaper.mp4")
        let localVideo2 = videoBackdropDir.appendingPathComponent("current_wallpaper.mp4")
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let moviesDir = home.appendingPathComponent("Movies/LiveWallpaper", isDirectory: true)
        let moviesVideo = moviesDir.appendingPathComponent("current_wallpaper.mp4")
        
        let containerDir = home.appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/LiveWallpaper", isDirectory: true)
        let containerVideo = containerDir.appendingPathComponent("current_wallpaper.mp4")
        
        let aerialVideosDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
        let aerialThumbDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
        
        let targetMov = aerialVideosDir.appendingPathComponent("FF9CB826-41B2-4A5E-A0AA-D4842AA26511.mov")
        let targetThumb = aerialThumbDir.appendingPathComponent("FF9CB826-41B2-4A5E-A0AA-D4842AA26511.png")
        
        Task.detached(priority: .background) {
            do {
                try FileManager.default.createDirectory(at: liveWallpaperDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: videoBackdropDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: moviesDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialVideosDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialThumbDir, withIntermediateDirectories: true)
                
                // Helper to avoid redundant multi-megabyte writes on startup
                func syncFileIfNeeded(from src: URL, to dst: URL) {
                    if FileManager.default.fileExists(atPath: dst.path) {
                        if let srcAttrs = try? FileManager.default.attributesOfItem(atPath: src.path),
                           let dstAttrs = try? FileManager.default.attributesOfItem(atPath: dst.path),
                           let srcSize = srcAttrs[.size] as? Int64,
                           let dstSize = dstAttrs[.size] as? Int64,
                           srcSize == dstSize {
                            return // Identical file already exists, zero I/O hitches!
                        }
                        try? FileManager.default.removeItem(at: dst)
                    }
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
                
                syncFileIfNeeded(from: sourceURL, to: localVideo1)
                syncFileIfNeeded(from: sourceURL, to: localVideo2)
                syncFileIfNeeded(from: sourceURL, to: moviesVideo)
                syncFileIfNeeded(from: sourceURL, to: containerVideo)
                syncFileIfNeeded(from: sourceURL, to: targetMov)
                
                // Extract matching thumbnail for macOS native aerials
                if !FileManager.default.fileExists(atPath: targetThumb.path) {
                    let gen = AVAssetImageGenerator(asset: asset)
                    gen.appliesPreferredTrackTransform = true
                    var targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                    if let duration = try? await asset.load(.duration), CMTimeGetSeconds(duration) <= 1.0 {
                        targetTime = .zero
                    }
                    if let (cgImage, _) = try? await gen.image(at: targetTime) {
                        let rep = NSBitmapImageRep(cgImage: cgImage)
                        if let pngData = rep.representation(using: .png, properties: [:]) {
                            try? pngData.write(to: targetThumb, options: .atomic)
                        }
                    }
                }
                
                // Configure Index.plist for Idle
                Self.ensureNativeAerialScreenSaverConfigured()
                
                // Configure com.apple.screensaver defaults to LiveWallpaper.saver with proper integer type 0
                let saverPath = "\(home.path)/Library/Screen Savers/LiveWallpaper.saver"
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
                task.arguments = ["-currentHost", "write", "com.apple.screensaver", "moduleDict", "-dict", "moduleName", "LiveWallpaper", "path", saverPath, "type", "-int", "0"]
                try? task.run()
                
                // Duplicate to VideoBackdrop.saver so whichever saver macOS looks for, it works!
                let legacySaver = "\(home.path)/Library/Screen Savers/VideoBackdrop.saver"
                if FileManager.default.fileExists(atPath: saverPath) {
                    try? FileManager.default.removeItem(atPath: legacySaver)
                    try? FileManager.default.copyItem(atPath: saverPath, toPath: legacySaver)
                }
                
                NSLog("[LockScreenPosterManager] Synchronized video to native Aerials and LiveWallpaper.saver!")
            } catch {
                NSLog("[LockScreenPosterManager] Warning syncing screensaver video: \(error.localizedDescription)")
            }
        }
    }
    
    private nonisolated static func updateIndexPlistForDesktop(stableURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            return
        }
        
        let configDict: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": "file://\(stableURL.path)"]
        ]
        guard let configData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else {
            return
        }
        
        let imageChoice: [String: Any] = [
            "Configuration": configData,
            "Files": [String](),
            "Provider": "com.apple.wallpaper.choice.image"
        ]
        
        let desktopDict: [String: Any] = [
            "Content": [
                "Choices": [imageChoice],
                "EncodedOptionValues": "$null",
                "Shuffle": "$null"
            ],
            "LastSet": Date(),
            "LastUse": Date()
        ]
        
        var modified = false
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Type"] = "individual"
            sysDefault["Desktop"] = desktopDict
            plist["SystemDefault"] = sysDefault
            modified = true
        }
        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces["Type"] = "individual"
            allSpaces["Desktop"] = desktopDict
            plist["AllSpacesAndDisplays"] = allSpaces
            modified = true
        }
        if var displays = plist["Displays"] as? [String: [String: Any]] {
            for (k, var disp) in displays {
                disp["Type"] = "individual"
                disp["Desktop"] = desktopDict
                displays[k] = disp
                modified = true
            }
            plist["Displays"] = displays
        }
        if var spaces = plist["Spaces"] as? [String: [String: Any]] {
            for (k, var space) in spaces {
                if var def = space["Default"] as? [String: Any] {
                    def["Type"] = "individual"
                    def["Desktop"] = desktopDict
                    space["Default"] = def
                    modified = true
                }
                if var dispMap = space["Displays"] as? [String: [String: Any]] {
                    for (dispKey, var disp) in dispMap {
                        disp["Type"] = "individual"
                        disp["Desktop"] = desktopDict
                        dispMap[dispKey] = disp
                        modified = true
                    }
                    space["Displays"] = dispMap
                }
                spaces[k] = space
            }
            plist["Spaces"] = spaces
        }
        
        if modified, let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? updatedData.write(to: indexURL, options: .atomic)
        }
    }
    
    public nonisolated static func ensureNativeAerialScreenSaverConfigured() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            return
        }
        
        let configDict: [String: Any] = ["assetID": "FF9CB826-41B2-4A5E-A0AA-D4842AA26511"]
        guard let configData = try? PropertyListSerialization.data(fromPropertyList: configDict, format: .binary, options: 0) else {
            return
        }
        
        let aerialChoice: [String: Any] = [
            "Configuration": configData,
            "Files": [String](),
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]
        
        let contentDict: [String: Any] = [
            "Choices": [aerialChoice],
            "EncodedOptionValues": "$null",
            "Shuffle": "$null"
        ]
        
        let idleDict: [String: Any] = [
            "Content": contentDict,
            "LastSet": Date(),
            "LastUse": Date()
        ]
        
        var modified = false
        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces["Type"] = "individual"
            allSpaces["Idle"] = idleDict
            plist["AllSpacesAndDisplays"] = allSpaces
            modified = true
        }
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Type"] = "individual"
            sysDefault["Idle"] = idleDict
            plist["SystemDefault"] = sysDefault
            modified = true
        }
        if var displays = plist["Displays"] as? [String: [String: Any]] {
            for (k, var disp) in displays {
                disp["Type"] = "individual"
                disp["Idle"] = idleDict
                displays[k] = disp
                modified = true
            }
            plist["Displays"] = displays
        }
        if var spaces = plist["Spaces"] as? [String: [String: Any]] {
            for (k, var space) in spaces {
                if var def = space["Default"] as? [String: Any] {
                    def["Type"] = "individual"
                    def["Idle"] = idleDict
                    space["Default"] = def
                    modified = true
                }
                if var dispMap = space["Displays"] as? [String: [String: Any]] {
                    for (dispKey, var disp) in dispMap {
                        disp["Type"] = "individual"
                        disp["Idle"] = idleDict
                        dispMap[dispKey] = disp
                        modified = true
                    }
                    space["Displays"] = dispMap
                }
                spaces[k] = space
                modified = true
            }
            plist["Spaces"] = spaces
        }
        
        if modified, let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? updatedData.write(to: indexURL, options: .atomic)
        }
    }
    
    /// Restores default macOS wallpaper and lock screen on quit
    public func restoreOriginalWallpapers() {
        NSLog("[LockScreenPosterManager] Restoring macOS default wallpaper and lock screen...")
        let defaultWallpaperURL = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
        
        // 1. Reset each screen to original wallpaper or macOS DefaultDesktop.heic
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            var targetURL = defaultWallpaperURL
            if let originalURL = originalWallpapers[id],
               !originalURL.path.contains("LiveWallpaper"),
               !originalURL.path.contains("VideoBackdrop"),
               !originalURL.path.contains("lockscreen"),
               FileManager.default.fileExists(atPath: originalURL.path) {
                targetURL = originalURL
            } else if let path = defaults.string(forKey: "originalWallpaper_\(id)"),
                      !path.contains("LiveWallpaper"),
                      !path.contains("VideoBackdrop"),
                      !path.contains("lockscreen"),
                      FileManager.default.fileExists(atPath: path) {
                targetURL = URL(fileURLWithPath: path)
            }
            
            try? NSWorkspace.shared.setDesktopImageURL(targetURL, for: screen, options: [:])
        }
        
        // 2. Remove /Library/Caches/Desktop Pictures/*/lockscreen.png so loginwindow reverts to default
        let systemCacheDir = "/Library/Caches/Desktop Pictures"
        if let items = try? FileManager.default.contentsOfDirectory(atPath: systemCacheDir) {
            for item in items {
                let userDir = (systemCacheDir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: userDir, isDirectory: &isDir), isDir.boolValue {
                    let lockscreenPNG = (userDir as NSString).appendingPathComponent("lockscreen.png")
                    if FileManager.default.fileExists(atPath: lockscreenPNG) {
                        try? FileManager.default.removeItem(atPath: lockscreenPNG)
                        NSLog("[LockScreenPosterManager] Removed lockscreen.png cache at: %@", lockscreenPNG)
                    }
                }
            }
        }
        
        // 3. Restore Index.plist from backup or point to DefaultDesktop.heic
        let home = FileManager.default.homeDirectoryForCurrentUser
        let storeDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("Index.plist")
        let backupURL = storeDir.appendingPathComponent("Index.plist.backup")
        
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.removeItem(at: indexURL)
            try? FileManager.default.copyItem(at: backupURL, to: indexURL)
            NSLog("[LockScreenPosterManager] Restored Index.plist from Index.plist.backup")
        } else {
            Self.updateIndexPlistForDesktop(stableURL: defaultWallpaperURL)
        }
        
        // 4. Update System Events via AppleScript
        let defPathString = defaultWallpaperURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            set defPic to POSIX file "\(defPathString)"
            repeat with d in desktops
                set picture of d to defPic
            end repeat
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
        }
        
        // 5. Gently signal WallpaperAgent to immediately apply the default wallpaper
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
    }
}
