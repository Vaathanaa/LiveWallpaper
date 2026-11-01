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
    
    public nonisolated static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    
    private nonisolated static func backupIndexPlistOnce() {
        let home = realHomeDirectory()
        let storeDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        let indexURL = storeDir.appendingPathComponent("Index.plist")
        let backupURL = storeDir.appendingPathComponent("Index.plist.backup")
        
        if FileManager.default.fileExists(atPath: indexURL.path) && !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: indexURL, to: backupURL)
            AppLogger.poster.info("Created system wallpaper Index.plist.backup")
        }
    }
    
    public func updateLockScreenPoster(for asset: AVAsset, at time: CMTime = .zero) {
        let home = Self.realHomeDirectory()
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let liveWallpaperDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        let videoBackdropDir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        let moviesDir = home.appendingPathComponent("Movies/LiveWallpaper", isDirectory: true)
        let saverResourceDir = home.appendingPathComponent("Library/Screen Savers/LiveWallpaper.saver/Contents/Resources", isDirectory: true)
        let legacySaverResourceDir = home.appendingPathComponent("Library/Screen Savers/VideoBackdrop.saver/Contents/Resources", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: liveWallpaperDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videoBackdropDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: moviesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: saverResourceDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: legacySaverResourceDir, withIntermediateDirectories: true)
        
        let stableURL = liveWallpaperDir.appendingPathComponent("lockscreen_poster.jpg")
        let backupStableURL = videoBackdropDir.appendingPathComponent("lockscreen_poster.jpg")
        let moviesPosterURL = moviesDir.appendingPathComponent("lockscreen_poster.jpg")
        let saverPosterURL = saverResourceDir.appendingPathComponent("lockscreen_poster.jpg")
        let legacySaverPosterURL = legacySaverResourceDir.appendingPathComponent("lockscreen_poster.jpg")
        
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
                
                // 1. Write high-quality JPEG poster for Application Support, Movies, and Screen Saver bundles
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    try? jpegData.write(to: stableURL, options: .atomic)
                    try? jpegData.write(to: backupStableURL, options: .atomic)
                    try? jpegData.write(to: moviesPosterURL, options: .atomic)
                    try? jpegData.write(to: saverPosterURL, options: .atomic)
                    try? jpegData.write(to: legacySaverPosterURL, options: .atomic)
                    
                    for url in [stableURL, backupStableURL, moviesPosterURL, saverPosterURL, legacySaverPosterURL] {
                        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                        let xattrTask = Process()
                        xattrTask.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                        xattrTask.arguments = ["-c", url.path]
                        try? xattrTask.run()
                    }
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
                                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockscreenPNG)
                                let xattrTask = Process()
                                xattrTask.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                                xattrTask.arguments = ["-c", lockscreenPNG]
                                try? xattrTask.run()
                                AppLogger.poster.info("Successfully updated system lockscreen.png at: \(lockscreenPNG, privacy: .private(mask: .hash))")
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
                            AppLogger.poster.warning("Warning setting desktop image: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    
                    LockScreenPosterManager.shared.posterURL = stableURL
                }
                
                // 4. Update Index.plist for Desktop choices with individual space/display mode
                Self.updateIndexPlistForDesktop(stableURL: stableURL)
                
                // 5. Signal WallpaperAgent to refresh Desktop and Lock Screen immediately
                let reloadTask = Process()
                reloadTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                reloadTask.arguments = ["WallpaperAgent"]
                try? reloadTask.run()
                
                // 6. Asynchronously notify System Events on background utility queue
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
                AppLogger.poster.error("Error extracting frame: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    /// Synchronizes the active video directly to macOS's native 120Hz Screen Saver and caches
    public func syncScreenSaverVideo(from sourceURL: URL, asset: AVAsset) {
        let home = Self.realHomeDirectory()
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let liveWallpaperDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        let videoBackdropDir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        
        let localVideo1 = liveWallpaperDir.appendingPathComponent("current_wallpaper.mp4")
        let localVideo2 = videoBackdropDir.appendingPathComponent("current_wallpaper.mp4")
        
        let moviesDir = home.appendingPathComponent("Movies/LiveWallpaper", isDirectory: true)
        let moviesVideo = moviesDir.appendingPathComponent("current_wallpaper.mp4")
        
        let containerDir = home.appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/LiveWallpaper", isDirectory: true)
        let containerVideo = containerDir.appendingPathComponent("current_wallpaper.mp4")
        
        let aerialVideosDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
        let aerialThumbDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
        
        // Native macOS Sequoia aerial video targets that WallpaperAgent plays
        let officialAerialIDs = [
            "C6AECFD2-A365-4504-9E2C-F86343F9421F", // macOS Sequoia / Sonoma Dark
            "4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19", // macOS Sequoia / Sonoma Light
            "11AB4259-C435-4F92-A108-D6B9CC6D2295", // macOS Sequoia / Sonoma Light Portrait
            "731140AB-82EF-47B5-B62C-285BA7E112FD", // macOS Sequoia / Sonoma Dark Portrait
            "FF9CB826-41B2-4A5E-A0AA-D4842AA26511"  // Custom fallback
        ]
        
        Task.detached(priority: .background) {
            do {
                try FileManager.default.createDirectory(at: liveWallpaperDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: videoBackdropDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: moviesDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialVideosDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialThumbDir, withIntermediateDirectories: true)
                
                // Helper to avoid redundant multi-megabyte writes on startup, while guaranteeing clean permissions & no quarantine
                func syncFileIfNeeded(from src: URL, to dst: URL, backupOriginal: Bool = false) {
                    if backupOriginal && FileManager.default.fileExists(atPath: dst.path) {
                        let backupURL = dst.appendingPathExtension("original")
                        if !FileManager.default.fileExists(atPath: backupURL.path) {
                            try? FileManager.default.copyItem(at: dst, to: backupURL)
                        }
                    }
                    if FileManager.default.fileExists(atPath: dst.path) {
                        if let srcAttrs = try? FileManager.default.attributesOfItem(atPath: src.path),
                           let dstAttrs = try? FileManager.default.attributesOfItem(atPath: dst.path),
                           let srcSize = srcAttrs[.size] as? Int64,
                           let dstSize = dstAttrs[.size] as? Int64,
                           srcSize == dstSize {
                            // Ensure permissions and strip quarantine even if identical
                            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dst.path)
                            let xattrTask = Process()
                            xattrTask.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                            xattrTask.arguments = ["-c", dst.path]
                            try? xattrTask.run()
                            return // Identical file already exists, zero I/O hitches!
                        }
                        try? FileManager.default.removeItem(at: dst)
                    }
                    try? FileManager.default.copyItem(at: src, to: dst)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dst.path)
                    let xattrTask = Process()
                    xattrTask.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                    xattrTask.arguments = ["-c", dst.path]
                    try? xattrTask.run()
                }
                
                syncFileIfNeeded(from: sourceURL, to: localVideo1)
                syncFileIfNeeded(from: sourceURL, to: localVideo2)
                syncFileIfNeeded(from: sourceURL, to: moviesVideo)
                syncFileIfNeeded(from: sourceURL, to: containerVideo)
                
                // Sync bundle resources directly into the .saver bundle so sandboxed legacyScreenSaver has instant access
                let saverResourceVideo = home.appendingPathComponent("Library/Screen Savers/LiveWallpaper.saver/Contents/Resources/current_wallpaper.mp4")
                let legacyResourceVideo = home.appendingPathComponent("Library/Screen Savers/VideoBackdrop.saver/Contents/Resources/current_wallpaper.mp4")
                try? FileManager.default.createDirectory(at: saverResourceVideo.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: legacyResourceVideo.deletingLastPathComponent(), withIntermediateDirectories: true)
                syncFileIfNeeded(from: sourceURL, to: saverResourceVideo)
                syncFileIfNeeded(from: sourceURL, to: legacyResourceVideo)
                
                // Also copy lockscreen poster to saver resources if available
                let stablePoster = liveWallpaperDir.appendingPathComponent("lockscreen_poster.jpg")
                if FileManager.default.fileExists(atPath: stablePoster.path) {
                    let saverPoster = home.appendingPathComponent("Library/Screen Savers/LiveWallpaper.saver/Contents/Resources/lockscreen_poster.jpg")
                    let legacyPoster = home.appendingPathComponent("Library/Screen Savers/VideoBackdrop.saver/Contents/Resources/lockscreen_poster.jpg")
                    syncFileIfNeeded(from: stablePoster, to: saverPoster)
                    syncFileIfNeeded(from: stablePoster, to: legacyPoster)
                }
                
                // Re-sign saver bundle ad-hoc to guarantee Gatekeeper validation
                let saverPath = "\(home.path)/Library/Screen Savers/LiveWallpaper.saver"
                let codesignTask = Process()
                codesignTask.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                codesignTask.arguments = ["--force", "--deep", "--sign", "-", saverPath]
                try? codesignTask.run()
                codesignTask.waitUntilExit()
                
                // Sync all native macOS aerial slots so WallpaperAgent ALWAYS plays the live video
                for aerialID in officialAerialIDs {
                    let aerialTarget = aerialVideosDir.appendingPathComponent("\(aerialID).mov")
                    syncFileIfNeeded(from: sourceURL, to: aerialTarget, backupOriginal: true)
                }
                
                // ALSO sync any existing downloaded aerial videos in this directory so whatever macOS chooses, it plays the live video!
                if let existingAerials = try? FileManager.default.contentsOfDirectory(atPath: aerialVideosDir.path) {
                    for item in existingAerials where item.hasSuffix(".mov") && !item.hasSuffix(".original") {
                        let target = aerialVideosDir.appendingPathComponent(item)
                        syncFileIfNeeded(from: sourceURL, to: target, backupOriginal: true)
                    }
                }
                
                // Extract matching thumbnail for macOS native aerials
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                var targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let duration = try? await asset.load(.duration), CMTimeGetSeconds(duration) <= 1.0 {
                    targetTime = .zero
                }
                if let (cgImage, _) = try? await gen.image(at: targetTime) {
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    if let pngData = rep.representation(using: .png, properties: [:]) {
                        for aerialID in officialAerialIDs {
                            let thumbURL = aerialThumbDir.appendingPathComponent("\(aerialID).png")
                            if !FileManager.default.fileExists(atPath: thumbURL.path) {
                                try? pngData.write(to: thumbURL, options: .atomic)
                                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: thumbURL.path)
                            }
                        }
                    }
                }
                
                // Configure Index.plist for Idle
                Self.ensureNativeAerialScreenSaverConfigured()
                
                // Configure com.apple.screensaver defaults to LiveWallpaper.saver with proper integer type 0
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
                task.arguments = ["-currentHost", "write", "com.apple.screensaver", "moduleDict", "-dict", "moduleName", "LiveWallpaper", "path", saverPath, "type", "-int", "0"]
                try? task.run()
                task.waitUntilExit()
                
                // Ensure System Events has LiveWallpaper set as the current active screen saver
                let tellSystemEvents = """
                tell application "System Events"
                    set current screen saver to screen saver "LiveWallpaper"
                end tell
                """
                if let appleScript = NSAppleScript(source: tellSystemEvents) {
                    var err: NSDictionary?
                    appleScript.executeAndReturnError(&err)
                }
                
                // Duplicate to VideoBackdrop.saver so whichever saver macOS looks for, it works!
                let legacySaver = "\(home.path)/Library/Screen Savers/VideoBackdrop.saver"
                if FileManager.default.fileExists(atPath: saverPath) {
                    try? FileManager.default.removeItem(atPath: legacySaver)
                    try? FileManager.default.copyItem(atPath: saverPath, toPath: legacySaver)
                }
                
                // Signal WallpaperAgent to refresh screen saver aerials
                let killTask = Process()
                killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                killTask.arguments = ["WallpaperAgent"]
                try? killTask.run()
                
                AppLogger.poster.info("Synchronized video to native Aerials and LiveWallpaper.saver!")
            } catch {
                AppLogger.poster.warning("Warning syncing screensaver video: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private nonisolated static func updateIndexPlistForDesktop(stableURL: URL) {
        let home = realHomeDirectory()
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            return
        }
        
        let fileURLString = stableURL.standardizedFileURL.absoluteString
        let configDict: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": fileURLString]
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
                modified = true
            }
            plist["Spaces"] = spaces
        }
        
        if modified, let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? updatedData.write(to: indexURL, options: .atomic)
        }
    }
    
    public nonisolated static func ensureNativeAerialScreenSaverConfigured() {
        let home = realHomeDirectory()
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            return
        }
        
        // Preserve current active aerial assetID from Index.plist if present, or fallback to standard Sequoia/Sonoma aerials
        var activeAssetID = "FF9CB826-41B2-4A5E-A0AA-D4842AA26511"
        if let allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any],
           let idle = allSpaces["Idle"] as? [String: Any],
           let content = idle["Content"] as? [String: Any],
           let choices = content["Choices"] as? [[String: Any]],
           let first = choices.first,
           let cfgData = first["Configuration"] as? Data,
           let cfg = (try? PropertyListSerialization.propertyList(from: cfgData, options: [], format: nil)) as? [String: Any],
           let existingID = cfg["assetID"] as? String {
            activeAssetID = existingID
        } else {
            let isDark = ResourceMonitor.isDarkMode()
            activeAssetID = isDark ? "C6AECFD2-A365-4504-9E2C-F86343F9421F" : "4DFE24ED-71CC-42D4-9FE8-3B8959B6CC19"
        }
        
        let configDict: [String: Any] = ["assetID": activeAssetID]
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
        AppLogger.poster.info("Restoring macOS default wallpaper and lock screen...")
        let defaultWallpaperURL = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
        let home = Self.realHomeDirectory()
        
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
                        AppLogger.poster.info("Removed lockscreen.png cache at: \(lockscreenPNG, privacy: .public)")
                    }
                }
            }
        }
        
        // 3. Restore all original aerial videos from backups
        let aerialVideosDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(atPath: aerialVideosDir.path) {
            for item in items where item.hasSuffix(".mov.original") {
                let backupMov = aerialVideosDir.appendingPathComponent(item)
                let originalName = String(item.dropLast(".original".count))
                let targetMov = aerialVideosDir.appendingPathComponent(originalName)
                try? FileManager.default.removeItem(at: targetMov)
                try? FileManager.default.copyItem(at: backupMov, to: targetMov)
                try? FileManager.default.removeItem(at: backupMov)
            }
        }
        
        // 4. Restore Index.plist Desktop and Idle to macOS Default
        Self.updateIndexPlistForDesktop(stableURL: defaultWallpaperURL)
        Self.restoreIndexPlistIdleToDefault()
        
        // 5. Update System Events via AppleScript
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
        
        // 6. Reset com.apple.screensaver defaults so legacy screensaver is deactivated
        let resetTask = Process()
        resetTask.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        resetTask.arguments = ["-currentHost", "delete", "com.apple.screensaver", "moduleDict"]
        try? resetTask.run()
        resetTask.waitUntilExit()
        
        // 7. Signal WallpaperAgent to immediately apply the default wallpaper and wait synchronously
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
        task.waitUntilExit()
        AppLogger.poster.info("macOS Default wallpaper successfully restored!")
    }
    
    public nonisolated static func restoreIndexPlistIdleToDefault() {
        let home = realHomeDirectory()
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard FileManager.default.fileExists(atPath: indexURL.path),
              let data = try? Data(contentsOf: indexURL),
              var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil) as? [String: Any] else {
            return
        }
        
        // Reset Idle to null so macOS reverts to default aerial/screen saver
        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces["Idle"] = "$null"
            plist["AllSpacesAndDisplays"] = allSpaces
        }
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Idle"] = "$null"
            plist["SystemDefault"] = sysDefault
        }
        if var displays = plist["Displays"] as? [String: [String: Any]] {
            for (k, var disp) in displays {
                disp["Idle"] = "$null"
                displays[k] = disp
            }
            plist["Displays"] = displays
        }
        if var spaces = plist["Spaces"] as? [String: [String: Any]] {
            for (k, var space) in spaces {
                if var def = space["Default"] as? [String: Any] {
                    def["Idle"] = "$null"
                    space["Default"] = def
                }
                if var dispMap = space["Displays"] as? [String: [String: Any]] {
                    for (dispKey, var disp) in dispMap {
                        disp["Idle"] = "$null"
                        dispMap[dispKey] = disp
                    }
                    space["Displays"] = dispMap
                }
                spaces[k] = space
            }
            plist["Spaces"] = spaces
        }
        
        if let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? updatedData.write(to: indexURL, options: .atomic)
        }
    }
}
