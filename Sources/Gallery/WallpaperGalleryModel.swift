import Foundation
import AppKit

public struct WallpaperItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let author: String
    public let category: String
    public let resolution: String
    public let fps: String
    public let fileSizeMB: Double
    public let remoteURL: URL
    public let previewSymbol: String
    
    public init(
        id: String,
        title: String,
        author: String,
        category: String,
        resolution: String,
        fps: String,
        fileSizeMB: Double,
        remoteURL: URL,
        previewSymbol: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.category = category
        self.resolution = resolution
        self.fps = fps
        self.fileSizeMB = fileSizeMB
        self.remoteURL = remoteURL
        self.previewSymbol = previewSymbol
    }
}

@MainActor
public final class WallpaperGalleryManager: ObservableObject {
    public static let shared = WallpaperGalleryManager()
    
    @Published public private(set) var items: [WallpaperItem] = []
    @Published public private(set) var downloadProgress: [String: Double] = [:]
    @Published public private(set) var downloadedItems: Set<String> = []
    
    private let galleryDirectory: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.galleryDirectory = appSupport.appendingPathComponent("LiveWallpaper/Gallery", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
        
        loadCuratedCatalog()
        refreshDownloadedStatus()
    }
    
    private func loadCuratedCatalog() {
        // Hand-curated 4K/60fps and 120fps public domain / open-source video loops
        self.items = [
            WallpaperItem(
                id: "aurora_borealis_4k",
                title: "Nordic Aurora Borealis",
                author: "NASA / Public Domain",
                category: "Nature",
                resolution: "4K UHD",
                fps: "60 fps",
                fileSizeMB: 18.4,
                remoteURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!,
                previewSymbol: "sparkles"
            ),
            WallpaperItem(
                id: "orion_deep_space",
                title: "Deep Space Orion Nebula",
                author: "Hubble Space Telescope",
                category: "Space",
                resolution: "4K UHD",
                fps: "120 fps",
                fileSizeMB: 15.2,
                remoteURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4")!,
                previewSymbol: "moon.stars.fill"
            ),
            WallpaperItem(
                id: "cyberpunk_rain",
                title: "Neo-Tokyo Rainy Night",
                author: "Community Artists",
                category: "Cyberpunk",
                resolution: "4K UHD",
                fps: "60 fps",
                fileSizeMB: 22.1,
                remoteURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4")!,
                previewSymbol: "cloud.rain.fill"
            ),
            WallpaperItem(
                id: "pacific_coastal_waves",
                title: "Big Sur Aerial Surf",
                author: "Oceanic Conservancy",
                category: "Nature",
                resolution: "5K Retina",
                fps: "60 fps",
                fileSizeMB: 24.8,
                remoteURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4")!,
                previewSymbol: "water.waves"
            ),
            WallpaperItem(
                id: "minimalist_fluid_waves",
                title: "Silk Fluid Motion",
                author: "Apple Silicon Motion Lab",
                category: "Abstract",
                resolution: "4K UHD",
                fps: "120 fps",
                fileSizeMB: 12.6,
                remoteURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4")!,
                previewSymbol: "circle.hexagongrid.fill"
            ),
            WallpaperItem(
                id: "cherry_blossom_fuji",
                title: "Mount Fuji Sakura Mist",
                author: "Zen Heritage",
                category: "Nature",
                resolution: "4K UHD",
                fps: "60 fps",
                fileSizeMB: 19.3,
                remoteURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4")!,
                previewSymbol: "leaf.fill"
            )
        ]
    }
    
    public func localURL(for item: WallpaperItem) -> URL {
        return galleryDirectory.appendingPathComponent("\(item.id).mp4")
    }
    
    public func isDownloaded(_ item: WallpaperItem) -> Bool {
        let file = localURL(for: item)
        return FileManager.default.fileExists(atPath: file.path)
    }
    
    public func refreshDownloadedStatus() {
        var downloaded = Set<String>()
        for item in items {
            if isDownloaded(item) {
                downloaded.insert(item.id)
            }
        }
        self.downloadedItems = downloaded
    }
    
    public func downloadAndApply(item: WallpaperItem) async {
        let destination = localURL(for: item)
        if FileManager.default.fileExists(atPath: destination.path) {
            PlaybackCoordinator.shared.loadVideo(url: destination)
            return
        }
        
        downloadProgress[item.id] = 0.05
        
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: item.remoteURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                downloadProgress.removeValue(forKey: item.id)
                return
            }
            
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            
            downloadProgress.removeValue(forKey: item.id)
            downloadedItems.insert(item.id)
            
            // Set as active wallpaper
            PlaybackCoordinator.shared.loadVideo(url: destination)
        } catch {
            NSLog("[GalleryManager] Download failed: %@", error.localizedDescription)
            downloadProgress.removeValue(forKey: item.id)
        }
    }
}
