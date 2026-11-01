import AppKit
import AVFoundation
import CoreImage

public final class VideoPlayerView: NSView {
    
    public var playerLayer: AVPlayerLayer {
        return (layer as? AVPlayerLayer) ?? AVPlayerLayer()
    }
    
    private let dimmingOverlayLayer = CALayer()
    private let readabilityGradientLayer = CAGradientLayer()
    private var isFrozen: Bool = false
    private var displayObserver: NSKeyValueObservation?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    deinit {
        displayObserver?.invalidate()
        displayObserver = nil
    }
    
    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        
        // Instant Startup Frame: Load cached lockscreen_poster.jpg so the very first millisecond
        // the backdrop window opens, it displays the crisp wallpaper frame with ZERO black gap!
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let posterURL = appSupport.appendingPathComponent("LiveWallpaper/lockscreen_poster.jpg")
        if FileManager.default.fileExists(atPath: posterURL.path),
           let image = NSImage(contentsOf: posterURL),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            layer?.contents = cgImage
            layer?.contentsGravity = .resizeAspectFill
        }
        
        dimmingOverlayLayer.backgroundColor = NSColor.black.cgColor
        dimmingOverlayLayer.opacity = 0.0
        dimmingOverlayLayer.isHidden = true
        dimmingOverlayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        dimmingOverlayLayer.actions = [
            "opacity": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "hidden": NSNull()
        ]
        layer?.addSublayer(dimmingOverlayLayer)
        
        // Widget Readability Cushion: Soft ambient gradient for menu bar and desktop widgets
        readabilityGradientLayer.colors = [
            NSColor.black.withAlphaComponent(0.35).cgColor,
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.40).cgColor
        ]
        readabilityGradientLayer.locations = [0.0, 0.08, 0.88, 1.0]
        readabilityGradientLayer.opacity = 0.0
        readabilityGradientLayer.isHidden = true
        readabilityGradientLayer.actions = [
            "opacity": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "hidden": NSNull()
        ]
        layer?.addSublayer(readabilityGradientLayer)
    }
    
    public override func layout() {
        super.layout()
        dimmingOverlayLayer.frame = bounds
        readabilityGradientLayer.frame = bounds
    }
    
    public override func makeBackingLayer() -> CALayer {
        let playerLayer = AVPlayerLayer()
        // Crucial for iPhone Mirroring & floating video overlays on Apple Silicon external displays:
        // Setting opacity = 0.999 ensures WindowServer treats this layer as a GPU-composited surface
        // rather than monopolizing the external monitor's single hardware video direct-scanout plane
        // (preventing iPhone Mirroring tearing/glitches).
        // Setting isOpaque = true informs CoreAnimation that video pixel buffers have full alpha,
        // which eliminates WindowServer cursor compositor alpha-blending bugs (preventing stray black pixels
        // tracking custom-scaled accessibility mouse pointers).
        playerLayer.isOpaque = true
        playerLayer.opacity = 1.0
        playerLayer.drawsAsynchronously = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.needsDisplayOnBoundsChange = false
        playerLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "transform": NSNull(),
            "filters": NSNull(),
            "opacity": NSNull()
        ]
        return playerLayer
    }
    
    public func attachPlayer(_ player: AVPlayer) {
        displayObserver?.invalidate()
        displayObserver = nil
        
        if playerLayer.player !== player {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.35
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            playerLayer.add(transition, forKey: "playerCrossfade")
            playerLayer.player = player
        }
        
        if playerLayer.isReadyForDisplay {
            unfreezeCurrentFrame()
        } else {
            displayObserver = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                if layer.isReadyForDisplay {
                    Task { @MainActor [weak self] in
                        self?.unfreezeCurrentFrame()
                        self?.displayObserver?.invalidate()
                        self?.displayObserver = nil
                    }
                }
            }
            
            // Safety fallback timeout in case video has no visual track
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                if self.displayObserver != nil {
                    self.unfreezeCurrentFrame()
                    self.displayObserver?.invalidate()
                    self.displayObserver = nil
                }
            }
        }
    }
    
    public func detachPlayer(preserveFrame: Bool = true) {
        displayObserver?.invalidate()
        displayObserver = nil
        if preserveFrame {
            freezeCurrentFrame()
        }
        playerLayer.player = nil
    }
    
    public func freezeCurrentFrame() {
        guard let player = playerLayer.player,
              let item = player.currentItem else { return }
        isFrozen = true
        let asset = item.asset
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        // Fast synchronous frame grab to guarantee frame is preserved before queue flushes
        if let syncCGImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.playerLayer.contents = syncCGImage
            CATransaction.commit()
            WallpaperColorHarmony.shared.extractPalette(from: syncCGImage)
            return
        }
        
        // Asynchronous thumbnail generation fallback
        Task.detached(priority: .userInitiated) {
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if self.isFrozen {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.playerLayer.contents = cgImage
                    CATransaction.commit()
                }
                WallpaperColorHarmony.shared.extractPalette(from: cgImage)
            }
        }
    }
    
    public func refreshDominantColor() {
        guard let player = playerLayer.player,
              let item = player.currentItem else { return }
        let asset = item.asset
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        Task.detached(priority: .utility) {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                await MainActor.run {
                    WallpaperColorHarmony.shared.extractPalette(from: cgImage)
                }
            }
        }
    }
    
    public func unfreezeCurrentFrame() {
        guard playerLayer.player?.currentItem != nil else { return }
        
        if playerLayer.isReadyForDisplay {
            displayObserver?.invalidate()
            displayObserver = nil
            isFrozen = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.contents = nil
            CATransaction.commit()
        } else {
            displayObserver?.invalidate()
            displayObserver = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                if layer.isReadyForDisplay {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.isFrozen = false
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.playerLayer.contents = nil
                        CATransaction.commit()
                        self.displayObserver?.invalidate()
                        self.displayObserver = nil
                    }
                }
            }
            
            // Safety fallback timeout in case video has no visual track
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                if self.displayObserver != nil {
                    self.isFrozen = false
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.playerLayer.contents = nil
                    CATransaction.commit()
                    self.displayObserver?.invalidate()
                    self.displayObserver = nil
                }
            }
        }
    }
    
    public func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = gravity
    }
    
    public func applyFilters(
        dimming: Double,
        blur: Double,
        saturation: Double,
        contrast: Double,
        vignette: Double = 0.0,
        exposure: Double = 0.0,
        widgetReadability: Bool = false
    ) {
        // Dimming overlay
        let clampedDim = max(0.0, min(0.9, dimming))
        dimmingOverlayLayer.opacity = Float(clampedDim)
        dimmingOverlayLayer.isHidden = (clampedDim <= 0.001)
        
        // Widget Readability Cushion
        readabilityGradientLayer.opacity = widgetReadability ? 1.0 : 0.0
        readabilityGradientLayer.isHidden = !widgetReadability
        
        // CoreImage post-processing filters
        var filters: [CIFilter] = []
        
        if saturation != 1.0 || contrast != 1.0 {
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
                colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
                filters.append(colorFilter)
            }
        }
        
        if exposure != 0.0 {
            if let expFilter = CIFilter(name: "CIExposureAdjust") {
                expFilter.setValue(exposure, forKey: kCIInputEVKey)
                filters.append(expFilter)
            }
        }
        
        if vignette > 0.01 {
            if let vigFilter = CIFilter(name: "CIVignette") {
                vigFilter.setValue(vignette * 2.0, forKey: kCIInputIntensityKey)
                vigFilter.setValue(2.0, forKey: kCIInputRadiusKey)
                filters.append(vigFilter)
            }
        }
        
        if blur > 0.1 {
            if let blurFilter = CIFilter(name: "CIGaussianBlur") {
                blurFilter.setValue(blur, forKey: kCIInputRadiusKey)
                filters.append(blurFilter)
            }
        }
        
        playerLayer.filters = filters.isEmpty ? nil : filters
    }
}
