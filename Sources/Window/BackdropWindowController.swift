import AppKit
import AVFoundation
import QuartzCore

@MainActor
public final class BackdropWindowController: NSWindowController {
    
    public let screen: NSScreen
    public let displayID: CGDirectDisplayID
    
    private let backdropWindow: BackdropWindow
    private let containerView: NSView
    
    // Multi-plane Depth Layers
    private let backgroundPlane: NSView
    private let foregroundPlane: NSView
    
    public let playerView: VideoPlayerView
    public let webView: WebBackdropView
    public let particleView: ParticleOverlayView
    
    // Per-monitor independent spring physics (zero multi-monitor coordinate jumping)
    private var currentX: Double = 0.0
    private var currentY: Double = 0.0
    private var velX: Double = 0.0
    private var velY: Double = 0.0
    private var wasResting: Bool = true
    
    public init(screen: NSScreen, levelMode: WindowLevelMode, videoGravity: AVLayerVideoGravity) {
        self.screen = screen
        self.displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        
        let window = BackdropWindow(screen: screen, levelMode: levelMode)
        self.backdropWindow = window
        
        let screenBounds = NSRect(origin: .zero, size: screen.frame.size)
        
        // Root Container: Translucent blended backing allows WindowServer GPU compositing
        // without monopolizing the external monitor's hardware video scanout plane
        let root = NSView(frame: screenBounds)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.isOpaque = false
        root.layer?.allowsEdgeAntialiasing = false
        self.containerView = root
        
        // Background Depth Plane (Video / Web Shaders)
        let bgPlane = NSView(frame: screenBounds)
        bgPlane.wantsLayer = true
        bgPlane.layer?.backgroundColor = NSColor.clear.cgColor
        bgPlane.layer?.isOpaque = false
        bgPlane.layer?.allowsEdgeAntialiasing = false
        self.backgroundPlane = bgPlane
        root.addSubview(bgPlane)
        
        // Video Player View (Inside Background Plane)
        let pView = VideoPlayerView(frame: screenBounds)
        pView.autoresizingMask = [.width, .height]
        pView.setVideoGravity(videoGravity)
        self.playerView = pView
        bgPlane.addSubview(pView)
        
        // Web / Shader View (Inside Background Plane)
        let wView = WebBackdropView(frame: screenBounds)
        wView.autoresizingMask = [.width, .height]
        wView.isHidden = true
        self.webView = wView
        bgPlane.addSubview(wView)
        
        // Foreground Depth Plane (Particles floating in front of screen)
        let fgPlane = NSView(frame: screenBounds)
        fgPlane.wantsLayer = true
        fgPlane.layer?.backgroundColor = NSColor.clear.cgColor
        fgPlane.layer?.allowsEdgeAntialiasing = false
        self.foregroundPlane = fgPlane
        root.addSubview(fgPlane)
        
        // Particle Weather Overlay (Inside Foreground Plane)
        let ptView = ParticleOverlayView(frame: screenBounds)
        ptView.autoresizingMask = [.width, .height]
        ptView.isHidden = true
        self.particleView = ptView
        fgPlane.addSubview(ptView)
        
        window.contentView = root
        
        super.init(window: window)
        
        updateFramerateMode(AppSettings.shared.targetFPS)
        updateFilters()
        updateContentType()
        updateParticleOverlay()
        resetTransforms()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Content Layer Management
    
    public func updateContentType() {
        let settings = AppSettings.shared
        
        // Liquid ProMotion 120Hz Crossfade Dissolve
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.4
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        backgroundPlane.layer?.add(transition, forKey: "contentCrossfade")
        foregroundPlane.layer?.add(transition, forKey: "contentFGCrossfade")
        
        switch settings.contentType {
        case .video:
            backgroundPlane.layer?.backgroundColor = NSColor.clear.cgColor
            playerView.isHidden = false
            webView.isHidden = true
            webView.pause()
            updateParticleOverlay()
            
            if PlaybackCoordinator.shared.resourceMonitor.activePauseReasons.isEmpty {
                PlaybackCoordinator.shared.play()
            }
            
        case .web:
            backgroundPlane.layer?.backgroundColor = NSColor.clear.cgColor
            playerView.isHidden = true
            webView.isHidden = false
            PlaybackCoordinator.shared.pause()
            
            if let customURL = settings.webURLString, !customURL.isEmpty, let url = URL(string: customURL) {
                webView.loadURL(url)
            } else {
                webView.loadPreset(settings.selectedWebPreset)
            }
            webView.resume()
            updateParticleOverlay()
            
        case .particles:
            // Standalone particles: deep midnight obsidian backdrop for vivid glowing particle contrast
            backgroundPlane.layer?.backgroundColor = NSColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1.0).cgColor
            playerView.isHidden = true
            webView.isHidden = true
            webView.pause()
            PlaybackCoordinator.shared.pause()
            
            particleView.isHidden = false
            let activePreset = settings.particlePreset == .none ? .snow : settings.particlePreset
            particleView.setPreset(activePreset, force: true)
            particleView.resume()
        }
    }
    
    public func updateParticleOverlay() {
        let settings = AppSettings.shared
        
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.35
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        foregroundPlane.layer?.add(transition, forKey: "particleCrossfade")
        
        if settings.contentType == .particles {
            particleView.isHidden = false
            let preset = settings.particlePreset == .none ? .snow : settings.particlePreset
            particleView.setPreset(preset, force: true)
            particleView.resume()
        } else if settings.isParticleOverlayEnabled && settings.particlePreset != .none {
            particleView.isHidden = false
            particleView.setPreset(settings.particlePreset, force: true)
            particleView.resume()
        } else {
            particleView.isHidden = true
            particleView.pause()
        }
    }
    
    public func updateFilters() {
        let settings = AppSettings.shared
        playerView.applyFilters(
            dimming: settings.dimmingAmount,
            blur: settings.blurRadius,
            saturation: settings.saturationAmount,
            contrast: settings.contrastAmount
        )
    }
    
    // MARK: - Per-Monitor Fluid Spring Physics & Zero-Glitch Parallax
    
    public func tickParallax(mouseLocation: CGPoint, dt: Double) -> Bool {
        let settings = AppSettings.shared
        
        guard settings.isMouseInteractionEnabled, settings.parallaxIntensity > 0 else {
            if currentX != 0.0 || currentY != 0.0 {
                currentX = 0.0
                currentY = 0.0
                velX = 0.0
                velY = 0.0
                resetTransforms()
            }
            return true
        }
        
        // Calculate target coordinate localized to THIS monitor's geometry
        let screenFrame = screen.frame
        var rawX = 0.0
        var rawY = 0.0
        
        if screenFrame.contains(mouseLocation) {
            let halfW = max(1.0, screenFrame.width / 2.0)
            let halfH = max(1.0, screenFrame.height / 2.0)
            rawX = max(-1.0, min(1.0, (mouseLocation.x - screenFrame.midX) / halfW))
            rawY = max(-1.0, min(1.0, (mouseLocation.y - screenFrame.midY) / halfH))
            
            // Fix 1: Menu Bar Glitch Protection
            // As cursor enters the top menu bar region (rawY > 0.65 ... 1.0), softly cushion vertical motion
            // so the translucent menu bar background stays completely rock-solid without blur-flicker
            if rawY > 0.65 {
                let overflow = rawY - 0.65
                rawY = 0.65 + (overflow * 0.18)
            }
            
            // Fix 2: Radial Corner Soft-Knee Cushioning
            // In corners, diagonal distance is sqrt(x^2 + y^2) = 1.414.
            // Softly compress radial distance so corners never whip or "take too much"
            let r = hypot(rawX, rawY)
            if r > 0.72 {
                let excess = r - 0.72
                let compressedR = 0.72 + (excess / (1.0 + excess * 1.6))
                let scale = compressedR / r
                rawX *= scale
                rawY *= scale
            }
            
            // Fix 3: Top-Right Hot Corner Deadzone Protection
            // If cursor is within 35px of the top-right corner, gently cushion parallax
            let distFromTopRightX = screenFrame.maxX - mouseLocation.x
            let distFromTopRightY = screenFrame.maxY - mouseLocation.y
            if distFromTopRightX < 35 && distFromTopRightY < 35 {
                let cornerFactor = min(1.0, max(0.0, hypot(distFromTopRightX, distFromTopRightY) / 49.0))
                rawX *= (0.4 + 0.6 * cornerFactor)
                rawY *= (0.4 + 0.6 * cornerFactor)
            }
        }
        
        let targetX = rawX
        let targetY = rawY
        
        // Critically Damped Harmonic Oscillator (Spring-Mass-Damper):
        // omega = 2pi * f (f = 2.8 Hz for velvety glide)
        // zeta = 1.0 (True critical damping: guaranteed zero overshoot, zero jitter)
        let omega = 2.0 * .pi * 2.8
        let diffX = targetX - currentX
        let diffY = targetY - currentY
        
        let accelX = (omega * omega * diffX) - (2.0 * omega * velX)
        let accelY = (omega * omega * diffY) - (2.0 * omega * velY)
        
        velX += accelX * dt
        velY += accelY * dt
        
        currentX += velX * dt
        currentY += velY * dt
        
        let isResting = abs(diffX) < 0.0001 && abs(diffY) < 0.0001 && abs(velX) < 0.0001 && abs(velY) < 0.0001
        if isResting {
            currentX = targetX
            currentY = targetY
            velX = 0.0
            velY = 0.0
            if wasResting {
                return true
            }
            wasResting = true
            applyParallax(normX: currentX, normY: currentY, mouseLocation: mouseLocation)
            return true
        }
        
        wasResting = false
        applyParallax(normX: currentX, normY: currentY, mouseLocation: mouseLocation)
        return false
    }
    
    private func applyParallax(normX: Double, normY: Double, mouseLocation: CGPoint) {
        let settings = AppSettings.shared
        let intensity = CGFloat(settings.parallaxIntensity)
        
        // Gentle, cinematic base travel (14pt default)
        let baseOffset: CGFloat = 14.0 * intensity
        let bgScale: CGFloat = 1.04 // 4% overscan is clean and comfortable for 14pt travel
        
        let bgTx = -CGFloat(normX) * baseOffset * 0.75
        let bgTy = -CGFloat(normY) * baseOffset * 0.75
        
        let midX = containerView.bounds.midX
        let midY = containerView.bounds.midY
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // 1. Background Plane: Centered pivot transform around (midX, midY)
        var bgTransform = CATransform3DIdentity
        bgTransform = CATransform3DTranslate(bgTransform, midX, midY, 0)
        bgTransform = CATransform3DScale(bgTransform, bgScale, bgScale, 1.0)
        bgTransform = CATransform3DTranslate(bgTransform, bgTx, bgTy, 0)
        
        if settings.parallaxTiltEnabled {
            let maxPitch: CGFloat = (0.75 * .pi / 180.0) * intensity // Subtle 0.75 degrees
            let maxYaw: CGFloat = (0.95 * .pi / 180.0) * intensity   // Subtle 0.95 degrees
            var tilt = CATransform3DIdentity
            tilt.m34 = -1.0 / 2500.0 // Ultra-gentle natural depth, zero distortion
            tilt = CATransform3DRotate(tilt, -CGFloat(normY) * maxPitch, 1, 0, 0)
            tilt = CATransform3DRotate(tilt, CGFloat(normX) * maxYaw, 0, 1, 0)
            bgTransform = CATransform3DConcat(bgTransform, tilt)
        }
        
        bgTransform = CATransform3DTranslate(bgTransform, -midX, -midY, 0)
        backgroundPlane.layer?.transform = bgTransform
        
        // 2. Foreground Plane: Weather particles move at 1.4x parallax speed for deep separation
        if !particleView.isHidden {
            let fgTx = -CGFloat(normX) * baseOffset * 1.4
            let fgTy = -CGFloat(normY) * baseOffset * 1.4
            
            var fgTransform = CATransform3DIdentity
            fgTransform = CATransform3DTranslate(fgTransform, midX, midY, 0)
            fgTransform = CATransform3DTranslate(fgTransform, fgTx, fgTy, 0)
            
            if settings.parallaxTiltEnabled {
                let maxPitch: CGFloat = (0.75 * .pi / 180.0) * intensity
                let maxYaw: CGFloat = (0.95 * .pi / 180.0) * intensity
                fgTransform = CATransform3DRotate(fgTransform, -CGFloat(normY) * maxPitch, 1, 0, 0)
                fgTransform = CATransform3DRotate(fgTransform, CGFloat(normX) * maxYaw, 0, 1, 0)
            }
            
            fgTransform = CATransform3DTranslate(fgTransform, -midX, -midY, 0)
            foregroundPlane.layer?.transform = fgTransform
            
            particleView.updateMousePosition(normalizedX: normX, normalizedY: normY)
        }
        
        // 3. Forward to Web/Shader if active
        if !webView.isHidden {
            webView.updateMousePosition(normalizedX: normX, normalizedY: normY, point: mouseLocation)
        }
        
        CATransaction.commit()
    }
    
    public func resetTransforms() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let midX = containerView.bounds.midX
        let midY = containerView.bounds.midY
        
        let settings = AppSettings.shared
        let targetScale: CGFloat = (settings.isMouseInteractionEnabled && settings.parallaxIntensity > 0) ? 1.04 : 1.0
        
        var bgIdentity = CATransform3DIdentity
        if targetScale != 1.0 {
            bgIdentity = CATransform3DTranslate(bgIdentity, midX, midY, 0)
            bgIdentity = CATransform3DScale(bgIdentity, targetScale, targetScale, 1.0)
            bgIdentity = CATransform3DTranslate(bgIdentity, -midX, -midY, 0)
        }
        backgroundPlane.layer?.transform = bgIdentity
        
        foregroundPlane.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }
    
    public func showBackdrop() {
        guard let window = self.window else { return }
        window.orderFrontRegardless()
    }
    
    public func hideBackdrop() {
        guard let window = self.window else { return }
        window.orderOut(nil)
    }
    
    public func updateScreenConfiguration(_ newScreen: NSScreen) {
        backdropWindow.updateFrame(for: newScreen)
        let newBounds = NSRect(origin: .zero, size: newScreen.frame.size)
        
        containerView.frame = newBounds
        backgroundPlane.frame = newBounds
        foregroundPlane.frame = newBounds
        
        playerView.frame = newBounds
        webView.frame = newBounds
        particleView.frame = newBounds
        
        resetTransforms()
        updateFramerateMode(AppSettings.shared.targetFPS)
    }
    
    public func updateWindowLevel(_ mode: WindowLevelMode) {
        backdropWindow.updateWindowLevel(mode)
    }
    
    public func updateVideoGravity(_ gravity: AVLayerVideoGravity) {
        playerView.setVideoGravity(gravity)
    }
    
    public func attachPlayer(_ player: AVPlayer) {
        playerView.attachPlayer(player)
        updateContentType()
        backdropWindow.orderFrontRegardless()
    }
    
    public func detachPlayer() {
        playerView.detachPlayer()
    }
    
    public func freezeCurrentFrame() {
        playerView.freezeCurrentFrame()
    }
    
    public func unfreezeCurrentFrame() {
        playerView.unfreezeCurrentFrame()
    }
    
    public func updateFramerateMode(_ fps: TargetFPS) {}
    public func setDisplayLinkActive(_ active: Bool) {}
    
    public func setWindowVisible(_ visible: Bool) {
        guard let window = self.window else { return }
        if visible {
            window.orderFrontRegardless()
            if !webView.isHidden { webView.resume() }
            if !particleView.isHidden { particleView.resume() }
        } else {
            window.orderOut(nil)
            if !webView.isHidden { webView.pause() }
            if !particleView.isHidden { particleView.pause() }
        }
    }
    
    public func pauseInteractiveLayers() {
        webView.pause()
        particleView.pause()
    }
    
    public func resumeInteractiveLayers() {
        if !webView.isHidden { webView.resume() }
        if !particleView.isHidden { particleView.resume() }
    }
    
    public func tearDown() {
        detachPlayer()
        webView.pause()
        particleView.pause()
        window?.orderOut(nil)
        window?.close()
    }
}
