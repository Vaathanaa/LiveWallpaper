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
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                if !url.path.contains("poster_") && !url.path.contains("lockscreen_poster") && !url.path.contains("lockscreen.png") {
                    originalWallpapers[id] = url
                    defaults.set(url.path, forKey: "originalWallpaper_\(id)")
                }
            }
        }
    }
    
    public func updateLockScreenPoster(for asset: AVAsset, at time: CMTime = .zero) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let liveWallpaperDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        let videoBackdropDir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: liveWallpaperDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videoBackdropDir, withIntermediateDirectories: true)
        
        let stableURL = liveWallpaperDir.appendingPathComponent("lockscreen_poster.jpg")
        let backupStableURL = videoBackdropDir.appendingPathComponent("lockscreen_poster.jpg")
        
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
                
                // 1. Write high-quality JPEG poster for Application Support
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    try? jpegData.write(to: stableURL, options: .atomic)
                    try? jpegData.write(to: backupStableURL, options: .atomic)
                }
                
                // 2. CRITICAL for macOS Lock Screen: Write directly to /Library/Caches/Desktop Pictures/<user-uuid>/lockscreen.png
                // This is the direct system cache that macOS loginwindow and _securityagent use to render the Lock Screen wallpaper.
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    let systemCacheDir = "/Library/Caches/Desktop Pictures"
                    if let items = try? FileManager.default.contentsOfDirectory(atPath: systemCacheDir) {
                        for item in items {
                            let userDir = (systemCacheDir as NSString).appendingPathComponent(item)
                            var isDir: ObjCBool = false
                            if FileManager.default.fileExists(atPath: userDir, isDirectory: &isDir), isDir.boolValue {
                                let lockscreenPNG = (userDir as NSString).appendingPathComponent("lockscreen.png")
                                try? pngData.write(to: URL(fileURLWithPath: lockscreenPNG), options: .atomic)
                                NSLog("[LockScreenPosterManager] Successfully wrote macOS system lockscreen.png to: %@", lockscreenPNG)
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
                
                // 4. Update Index.plist for Desktop choices and gently signal WallpaperAgent
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
    
    /// Synchronizes the active video directly to macOS's native 120Hz Screen Saver
    public func syncScreenSaverVideo(from sourceURL: URL, asset: AVAsset) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let liveWallpaperDir = appSupport.appendingPathComponent("LiveWallpaper", isDirectory: true)
        let videoBackdropDir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        
        let localVideo1 = liveWallpaperDir.appendingPathComponent("current_wallpaper.mp4")
        let localVideo2 = videoBackdropDir.appendingPathComponent("current_wallpaper.mp4")
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let aerialVideosDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
        let aerialThumbDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
        
        let targetMov = aerialVideosDir.appendingPathComponent("FF9CB826-41B2-4A5E-A0AA-D4842AA26511.mov")
        let targetThumb = aerialThumbDir.appendingPathComponent("FF9CB826-41B2-4A5E-A0AA-D4842AA26511.png")
        
        Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(at: liveWallpaperDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: videoBackdropDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialVideosDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialThumbDir, withIntermediateDirectories: true)
                
                // Copy to localVideo1
                if FileManager.default.fileExists(atPath: localVideo1.path) {
                    try? FileManager.default.removeItem(at: localVideo1)
                }
                try? FileManager.default.copyItem(at: sourceURL, to: localVideo1)
                
                // Copy to localVideo2
                if FileManager.default.fileExists(atPath: localVideo2.path) {
                    try? FileManager.default.removeItem(at: localVideo2)
                }
                try? FileManager.default.copyItem(at: sourceURL, to: localVideo2)
                
                // Copy to native aerial screensaver slot
                if FileManager.default.fileExists(atPath: targetMov.path) {
                    try? FileManager.default.removeItem(at: targetMov)
                }
                try? FileManager.default.copyItem(at: sourceURL, to: targetMov)
                
                // Extract matching thumbnail
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
                
                // Configure Index.plist for Idle
                Self.ensureNativeAerialScreenSaverConfigured()
                
                // Configure com.apple.screensaver defaults to LiveWallpaper.saver
                let saverPath = "\(home.path)/Library/Screen Savers/LiveWallpaper.saver"
                let dict: [String: Any] = [
                    "moduleName": "LiveWallpaper",
                    "path": saverPath,
                    "type": 0
                ]
                UserDefaults(suiteName: "com.apple.screensaver")?.set(dict, forKey: "moduleDict")
                
                // Duplicate to VideoBackdrop.saver so whichever saver macOS loads, it works!
                let legacySaver = "\(home.path)/Library/Screen Savers/VideoBackdrop.saver"
                if FileManager.default.fileExists(atPath: saverPath) {
                    try? FileManager.default.removeItem(atPath: legacySaver)
                    try? FileManager.default.copyItem(atPath: saverPath, toPath: legacySaver)
                }
                
                NSLog("[LockScreenPosterManager] Synchronized video to both native Aerials and LiveWallpaper.saver!")
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
            sysDefault["Desktop"] = desktopDict
            plist["SystemDefault"] = sysDefault
            modified = true
        }
        if var allSpaces = plist["AllSpacesAndDisplays"] as? [String: Any] {
            allSpaces["Desktop"] = desktopDict
            plist["AllSpacesAndDisplays"] = allSpaces
            modified = true
        }
        if var displays = plist["Displays"] as? [String: [String: Any]] {
            for (k, var disp) in displays {
                disp["Desktop"] = desktopDict
                displays[k] = disp
                modified = true
            }
            plist["Displays"] = displays
        }
        if var spaces = plist["Spaces"] as? [String: [String: Any]] {
            for (k, var space) in spaces {
                if var def = space["Default"] as? [String: Any] {
                    def["Desktop"] = desktopDict
                    space["Default"] = def
                    spaces[k] = space
                    modified = true
                }
            }
            plist["Spaces"] = spaces
        }
        
        if modified, let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? updatedData.write(to: indexURL, options: .atomic)
            
            // Gently reload WallpaperAgent so macOS immediately reflects the new Lock Screen / Desktop picture
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                task.arguments = ["WallpaperAgent"]
                try? task.run()
            }
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
            allSpaces["Idle"] = idleDict
            plist["AllSpacesAndDisplays"] = allSpaces
            modified = true
        }
        if var sysDefault = plist["SystemDefault"] as? [String: Any] {
            sysDefault["Idle"] = idleDict
            plist["SystemDefault"] = sysDefault
            modified = true
        }
        if var displays = plist["Displays"] as? [String: [String: Any]] {
            for (k, var disp) in displays {
                disp["Idle"] = idleDict
                displays[k] = disp
                modified = true
            }
            plist["Displays"] = displays
        }
        if var spaces = plist["Spaces"] as? [String: [String: Any]] {
            for (k, var space) in spaces {
                if var def = space["Default"] as? [String: Any] {
                    def["Idle"] = idleDict
                    space["Default"] = def
                    spaces[k] = space
                    modified = true
                }
                if var dispMap = space["Displays"] as? [String: [String: Any]] {
                    for (dispKey, var disp) in dispMap {
                        disp["Idle"] = idleDict
                        dispMap[dispKey] = disp
                        modified = true
                    }
                    space["Displays"] = dispMap
                    spaces[k] = space
                    modified = true
                }
            }
            plist["Spaces"] = spaces
        }
        
        if modified, let updatedData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
            try? updatedData.write(to: indexURL, options: .atomic)
            
            DispatchQueue.global(qos: .utility).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                task.arguments = ["WallpaperAgent"]
                try? task.run()
            }
        }
    }
    
    public func restoreOriginalWallpapers() {
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            if let originalURL = originalWallpapers[id] {
                try? NSWorkspace.shared.setDesktopImageURL(originalURL, for: screen, options: [:])
            } else if let path = defaults.string(forKey: "originalWallpaper_\(id)") {
                let url = URL(fileURLWithPath: path)
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        }
    }
}
