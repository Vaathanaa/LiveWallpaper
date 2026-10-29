import AppKit
import AVFoundation
import CoreImage

public final class VideoPlayerView: NSView {
    
    public var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    private let dimmingOverlayLayer = CALayer()
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        
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
    }
    
    public override func layout() {
        super.layout()
        dimmingOverlayLayer.frame = bounds
    }
    
    public override func makeBackingLayer() -> CALayer {
        let playerLayer = AVPlayerLayer()
        // Crucial for iPhone Mirroring & floating video overlays on Apple Silicon external displays:
        // Setting isOpaque = false and opacity = 0.999 ensures WindowServer treats this layer as a
        // GPU-composited surface rather than monopolizing the external monitor's single hardware
        // video direct-scanout plane. This allows iPhone Mirroring to run seamlessly without tearing or glitches.
        playerLayer.isOpaque = false
        playerLayer.opacity = 0.999
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
        if playerLayer.player !== player {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.35
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            playerLayer.add(transition, forKey: "playerCrossfade")
            playerLayer.player = player
        }
        unfreezeCurrentFrame()
    }
    
    public func detachPlayer(preserveFrame: Bool = true) {
        if preserveFrame {
            freezeCurrentFrame()
        }
        playerLayer.player = nil
    }
    
    public func freezeCurrentFrame() {
        guard let player = playerLayer.player,
              let item = player.currentItem else { return }
        let asset = item.asset
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        
        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.contents = cgImage
            CATransaction.commit()
        }
    }
    
    public func unfreezeCurrentFrame() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.contents = nil
        CATransaction.commit()
    }
    
    public func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = gravity
    }
    
    public func applyFilters(dimming: Double, blur: Double, saturation: Double, contrast: Double) {
        // Dimming overlay (hide completely when 0 to bypass compositing pass)
        let clampedDim = max(0.0, min(0.9, dimming))
        dimmingOverlayLayer.opacity = Float(clampedDim)
        dimmingOverlayLayer.isHidden = (clampedDim <= 0.001)
        
        // CoreImage post-processing filters
        var filters: [CIFilter] = []
        
        if saturation != 1.0 || contrast != 1.0 {
            if let colorFilter = CIFilter(name: "CIColorControls") {
                colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
                colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
                filters.append(colorFilter)
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
