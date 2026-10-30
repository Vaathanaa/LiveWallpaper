import ScreenSaver
import AVFoundation
import AppKit

@objc(LiveWallpaperScreenSaverView)
public class LiveWallpaperScreenSaverView: ScreenSaverView {
    
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    
    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupPlayer()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlayer()
    }
    
    public override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
    
    private func setupPlayer() {
        self.wantsLayer = true
        guard let layer = self.layer else { return }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let home = FileManager.default.homeDirectoryForCurrentUser
        
        let candidateVideos: [URL] = [
            appSupport.appendingPathComponent("LiveWallpaper/current_wallpaper.mp4"),
            appSupport.appendingPathComponent("VideoBackdrop/current_wallpaper.mp4"),
            home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos/FF9CB826-41B2-4A5E-A0AA-D4842AA26511.mov")
        ]
        
        let candidatePosters: [URL] = [
            appSupport.appendingPathComponent("LiveWallpaper/lockscreen_poster.jpg"),
            appSupport.appendingPathComponent("VideoBackdrop/lockscreen_poster.jpg")
        ]
        
        // 1. Instant fallback image: guarantees ZERO black frames
        for posterURL in candidatePosters {
            if let image = NSImage(contentsOf: posterURL),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                layer.contents = cgImage
                layer.contentsGravity = .resizeAspectFill
                break
            }
        }
        
        // 2. Discover video source
        var targetURL: URL?
        for candidate in candidateVideos {
            if FileManager.default.fileExists(atPath: candidate.path) {
                targetURL = candidate
                break
            }
        }
        
        if targetURL == nil {
            let defaults = UserDefaults(suiteName: "com.local.LiveWallpaper")
            if let path = defaults?.string(forKey: "videoPath"), FileManager.default.fileExists(atPath: path) {
                targetURL = URL(fileURLWithPath: path)
            } else {
                let fallback = "\(home.path)/Downloads/gothic-golden-crown-king-moewalls-com.mp4"
                if FileManager.default.fileExists(atPath: fallback) {
                    targetURL = URL(fileURLWithPath: fallback)
                }
            }
        }
        
        guard let url = targetURL else { return }
        
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2.0
        item.seekingWaitsForVideoCompositionRendering = false
        item.automaticallyPreservesTimeOffsetFromLive = false
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        
        self.playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.player = queuePlayer
        
        let pLayer = AVPlayerLayer(player: queuePlayer)
        pLayer.frame = bounds
        pLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        pLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(pLayer)
        self.playerLayer = pLayer
        
        // Start playback immediately
        queuePlayer.play()
    }
    
    public override func startAnimation() {
        super.startAnimation()
        player?.play()
    }
    
    public override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }
    
    public override func animateOneFrame() {
        super.animateOneFrame()
        if let p = player, p.rate == 0 {
            p.play()
        }
    }
    
    public override var hasConfigureSheet: Bool {
        return false
    }
}
