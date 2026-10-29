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
                if !url.path.contains("poster_") && !url.path.contains("lockscreen_poster") {
                    originalWallpapers[id] = url
                    defaults.set(url.path, forKey: "originalWallpaper_\(id)")
                }
            }
        }
    }
    
    public func updateLockScreenPoster(for asset: AVAsset, at time: CMTime = .zero) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Use a permanent, stable URL so every macOS virtual desktop/Space always has a valid file on disk
        let stableURL = dir.appendingPathComponent("lockscreen_poster.jpg")
        
        Task.detached(priority: .utility) {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 3840, height: 2160)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            
            // If requested at .zero, seek into the video slightly (1.0s) to avoid black fade-in frames
            var targetTime = time
            if targetTime <= .zero {
                if let duration = try? await asset.load(.duration), CMTimeGetSeconds(duration) > 2.0 {
                    targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
                }
            }
            
            do {
                let (cgImage, _) = try await gen.image(at: targetTime)
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    try jpegData.write(to: stableURL, options: .atomic)
                    
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
                        NSLog("[LockScreenPosterManager] Synced permanent live video poster to all desktop spaces.")
                    }
                    
                    // Asynchronously notify System Events on background utility queue to never hitch MainActor
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
                }
            } catch {
                NSLog("[LockScreenPosterManager] Error extracting frame: \(error.localizedDescription)")
            }
        }
    }
    
    /// Synchronizes the active video directly to macOS's native 120Hz Screen Saver
    public func syncScreenSaverVideo(from sourceURL: URL, asset: AVAsset) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VideoBackdrop", isDirectory: true)
        let localVideo = dir.appendingPathComponent("current_wallpaper.mp4")
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let aerialVideosDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
        let aerialThumbDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/thumbnails", isDirectory: true)
        
        let targetMov = aerialVideosDir.appendingPathComponent("FF9CB826-41B2-4A5E-A0AA-D4842AA26511.mov")
        let targetThumb = aerialThumbDir.appendingPathComponent("FF9CB826-41B2-4A5E-A0AA-D4842AA26511.png")
        
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialVideosDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: aerialThumbDir, withIntermediateDirectories: true)
                
                // Keep local video updated for VideoBackdrop.saver
                if FileManager.default.fileExists(atPath: localVideo.path) {
                    try? FileManager.default.removeItem(at: localVideo)
                }
                try? FileManager.default.copyItem(at: sourceURL, to: localVideo)
                
                // Copy the new video to the native aerial screensaver slot
                if FileManager.default.fileExists(atPath: targetMov.path) {
                    try? FileManager.default.removeItem(at: targetMov)
                }
                try FileManager.default.copyItem(at: sourceURL, to: targetMov)
                
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
                
                await MainActor.run {
                    self.ensureNativeAerialScreenSaverConfigured()
                    NSLog("[LockScreenPosterManager] Synchronized new video to native macOS Screen Saver!")
                }
            } catch {
                NSLog("[LockScreenPosterManager] Warning syncing screensaver video: \(error.localizedDescription)")
            }
        }
    }
    
    public func ensureNativeAerialScreenSaverConfigured() {
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
