import AppKit
import QuartzCore

@MainActor
public final class ParticleOverlayView: NSView {
    
    private let emitterLayer = CAEmitterLayer()
    private var currentPreset: ParticlePreset = .none
    private var isCurrentlyPaused: Bool = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }
    
    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        emitterLayer.frame = bounds
        emitterLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        emitterLayer.renderMode = .additive
        emitterLayer.masksToBounds = false
        layer?.addSublayer(emitterLayer)
    }
    
    public override func layout() {
        super.layout()
        emitterLayer.frame = bounds
        updateEmitterGeometry()
    }
    
    // MARK: - Preset Configuration
    
    public func setPreset(_ preset: ParticlePreset, force: Bool = false) {
        if !force && currentPreset == preset && !(emitterLayer.emitterCells?.isEmpty ?? true) {
            return
        }
        currentPreset = preset
        
        emitterLayer.emitterCells?.removeAll()
        emitterLayer.sublayers?.removeAll()
        
        if preset == .none {
            emitterLayer.birthRate = 0
            return
        }
        
        emitterLayer.birthRate = isCurrentlyPaused ? 0.0 : 1.0
        emitterLayer.speed = isCurrentlyPaused ? 0.0 : 1.0
        updateEmitterGeometry()
        
        switch preset {
        case .none:
            break
        case .snow:
            setupSnow()
        case .sakura:
            setupSakura()
        case .rain:
            setupRain()
        case .embers:
            setupEmbers()
        case .stars:
            setupStars()
        case .matrix:
            setupMatrix()
        }
    }
    
    private func updateEmitterGeometry() {
        let width = bounds.width > 0 ? bounds.width : NSScreen.main?.frame.width ?? 1920
        let height = bounds.height > 0 ? bounds.height : NSScreen.main?.frame.height ?? 1080
        
        switch currentPreset {
        case .snow, .sakura, .rain, .matrix:
            // Emit from the top edge across full screen width
            emitterLayer.emitterPosition = CGPoint(x: width / 2.0, y: height + 20)
            emitterLayer.emitterShape = .line
            emitterLayer.emitterSize = CGSize(width: width * 1.2, height: 10)
        case .embers:
            // Emit from the bottom edge rising upwards
            emitterLayer.emitterPosition = CGPoint(x: width / 2.0, y: -20)
            emitterLayer.emitterShape = .line
            emitterLayer.emitterSize = CGSize(width: width * 1.1, height: 10)
        case .stars:
            // Emit throughout the volume
            emitterLayer.emitterPosition = CGPoint(x: width / 2.0, y: height / 2.0)
            emitterLayer.emitterShape = .rectangle
            emitterLayer.emitterSize = CGSize(width: width, height: height)
        case .none:
            break
        }
    }
    
    // MARK: - Procedural Particle Generator
    
    private func setupSnow() {
        emitterLayer.renderMode = .additive
        
        let cell = CAEmitterCell()
        cell.name = "snow"
        cell.contents = createCircleTexture(radius: 8, color: NSColor(white: 1.0, alpha: 0.85), blur: true)
        cell.birthRate = 35
        cell.lifetime = 14.0
        cell.velocity = 60
        cell.velocityRange = 30
        cell.emissionLongitude = -.pi / 2 // Downward in AppKit coordinate space
        cell.emissionRange = .pi / 8
        cell.scale = 0.5
        cell.scaleRange = 0.35
        cell.spin = 0.2
        cell.spinRange = 0.5
        cell.alphaSpeed = -0.04
        cell.color = NSColor(white: 0.95, alpha: 0.9).cgColor
        
        let smallCell = CAEmitterCell()
        smallCell.name = "snowSmall"
        smallCell.contents = createCircleTexture(radius: 4, color: NSColor(white: 1.0, alpha: 0.7), blur: false)
        smallCell.birthRate = 50
        smallCell.lifetime = 18.0
        smallCell.velocity = 35
        smallCell.velocityRange = 20
        smallCell.emissionLongitude = -.pi / 2
        smallCell.emissionRange = .pi / 12
        smallCell.scale = 0.4
        smallCell.scaleRange = 0.2
        smallCell.alphaSpeed = -0.02
        smallCell.color = NSColor(white: 1.0, alpha: 0.65).cgColor
        
        emitterLayer.emitterCells = [cell, smallCell]
    }
    
    private func setupSakura() {
        emitterLayer.renderMode = .oldestFirst
        
        let cell = CAEmitterCell()
        cell.name = "petal"
        cell.contents = createPetalTexture()
        cell.birthRate = 18
        cell.lifetime = 15.0
        cell.velocity = 55
        cell.velocityRange = 25
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 6
        cell.scale = 0.5
        cell.scaleRange = 0.25
        cell.spin = 0.8
        cell.spinRange = 1.2
        cell.color = NSColor(red: 1.0, green: 0.75, blue: 0.82, alpha: 0.85).cgColor
        cell.redRange = 0.1
        cell.greenRange = 0.1
        
        emitterLayer.emitterCells = [cell]
    }
    
    private func setupRain() {
        emitterLayer.renderMode = .additive
        
        let drop = CAEmitterCell()
        drop.name = "rain"
        drop.contents = createRainStreakTexture()
        drop.birthRate = 180
        drop.lifetime = 4.0
        drop.velocity = 800
        drop.velocityRange = 200
        drop.emissionLongitude = -.pi / 2 // Straight down
        drop.emissionRange = .pi / 32
        drop.scale = 0.6
        drop.scaleRange = 0.2
        drop.color = NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.6).cgColor
        
        emitterLayer.emitterCells = [drop]
    }
    
    private func setupEmbers() {
        emitterLayer.renderMode = .additive
        
        let ember = CAEmitterCell()
        ember.name = "ember"
        ember.contents = createCircleTexture(radius: 6, color: NSColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 0.9), blur: true)
        ember.birthRate = 45
        ember.lifetime = 8.0
        ember.velocity = 90
        ember.velocityRange = 40
        ember.emissionLongitude = .pi / 2 // Upward in AppKit coordinate space
        ember.emissionRange = .pi / 5
        ember.scale = 0.4
        ember.scaleRange = 0.25
        ember.color = NSColor(red: 1.0, green: 0.4, blue: 0.05, alpha: 0.8).cgColor
        ember.alphaSpeed = -0.1
        ember.redSpeed = -0.05
        ember.greenSpeed = -0.1
        
        let microEmber = CAEmitterCell()
        microEmber.name = "microEmber"
        microEmber.contents = createCircleTexture(radius: 3, color: NSColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.95), blur: false)
        microEmber.birthRate = 60
        microEmber.lifetime = 6.0
        microEmber.velocity = 120
        microEmber.velocityRange = 50
        microEmber.emissionLongitude = .pi / 2
        microEmber.emissionRange = .pi / 4
        microEmber.scale = 0.3
        microEmber.scaleRange = 0.15
        microEmber.alphaSpeed = -0.12
        
        emitterLayer.emitterCells = [ember, microEmber]
    }
    
    private func setupStars() {
        emitterLayer.renderMode = .additive
        
        let star = CAEmitterCell()
        star.name = "star"
        star.contents = createCircleTexture(radius: 4, color: NSColor(white: 1.0, alpha: 0.9), blur: true)
        star.birthRate = 25
        star.lifetime = 10.0
        star.velocity = 5
        star.velocityRange = 5
        star.emissionRange = .pi * 2
        star.scale = 0.4
        star.scaleRange = 0.3
        star.alphaSpeed = -0.08
        star.color = NSColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 0.85).cgColor
        
        emitterLayer.emitterCells = [star]
    }
    
    private func setupMatrix() {
        emitterLayer.renderMode = .additive
        
        let code = CAEmitterCell()
        code.name = "matrix"
        code.contents = createMatrixGlyphTexture()
        code.birthRate = 60
        code.lifetime = 6.0
        code.velocity = 220
        code.velocityRange = 80
        code.emissionLongitude = -.pi / 2 // Downward
        code.emissionRange = 0.02
        code.scale = 0.5
        code.scaleRange = 0.2
        code.color = NSColor(red: 0.1, green: 1.0, blue: 0.3, alpha: 0.85).cgColor
        code.alphaSpeed = -0.14
        
        emitterLayer.emitterCells = [code]
    }
    
    // MARK: - Mouse Wind & Interactive Drift
    
    public func updateMousePosition(normalizedX: Double, normalizedY: Double) {
        guard !isCurrentlyPaused, currentPreset != .none, AppSettings.shared.isMouseInteractionEnabled else { return }
        
        // Tilt the emission angle subtly in the direction of mouse movement (wind simulation)
        let windAngle = normalizedX * 0.25 // subtle tilt up to ~14 degrees
        
        if let cells = emitterLayer.emitterCells {
            for cell in cells {
                switch currentPreset {
                case .snow, .sakura, .matrix:
                    cell.emissionLongitude = (-.pi / 2) + windAngle
                    cell.xAcceleration = CGFloat(normalizedX * 35.0)
                case .rain:
                    cell.emissionLongitude = (-.pi / 2) + (windAngle * 0.6)
                    cell.xAcceleration = CGFloat(normalizedX * 60.0)
                case .embers:
                    cell.emissionLongitude = (.pi / 2) + windAngle
                    cell.xAcceleration = CGFloat(normalizedX * 45.0)
                case .stars:
                    cell.xAcceleration = CGFloat(normalizedX * 10.0)
                    cell.yAcceleration = CGFloat(normalizedY * 10.0)
                case .none:
                    break
                }
            }
        }
    }
    
    // MARK: - Power & Occlusion Management
    
    public func pause() {
        guard !isCurrentlyPaused else { return }
        isCurrentlyPaused = true
        emitterLayer.birthRate = 0.0
        emitterLayer.speed = 0.0
    }
    
    public func resume() {
        isCurrentlyPaused = false
        emitterLayer.speed = 1.0
        emitterLayer.birthRate = (currentPreset != .none) ? 1.0 : 0.0
        if currentPreset != .none && (emitterLayer.emitterCells == nil || emitterLayer.emitterCells?.isEmpty == true) {
            setPreset(currentPreset, force: true)
        }
    }
    
    // MARK: - Texture Synthesis Utilities (Zero external file dependencies)
    
    private func createCircleTexture(radius: CGFloat, color: NSColor, blur: Bool) -> CGImage? {
        let size = CGSize(width: radius * 2, height: radius * 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        let rect = CGRect(origin: .zero, size: size)
        if blur {
            let locations: [CGFloat] = [0.0, 0.5, 1.0]
            let colors = [
                color.cgColor,
                color.withAlphaComponent(color.alphaComponent * 0.4).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ] as CFArray
            
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsAfterEndLocation)
            }
        } else {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect)
        }
        
        return ctx.makeImage()
    }
    
    private func createPetalTexture() -> CGImage? {
        let size = CGSize(width: 24, height: 28)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 12, y: 2))
        path.addQuadCurve(to: CGPoint(x: 22, y: 16), control: CGPoint(x: 23, y: 7))
        path.addQuadCurve(to: CGPoint(x: 12, y: 26), control: CGPoint(x: 19, y: 23))
        path.addQuadCurve(to: CGPoint(x: 2, y: 16), control: CGPoint(x: 5, y: 23))
        path.addQuadCurve(to: CGPoint(x: 12, y: 2), control: CGPoint(x: 1, y: 7))
        path.closeSubpath()
        
        ctx.addPath(path)
        ctx.setFillColor(NSColor(red: 1.0, green: 0.8, blue: 0.86, alpha: 0.95).cgColor)
        ctx.fillPath()
        
        return ctx.makeImage()
    }
    
    private func createRainStreakTexture() -> CGImage? {
        let size = CGSize(width: 3, height: 40)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        let locations: [CGFloat] = [0.0, 0.8, 1.0]
        let colors = [
            NSColor(red: 0.75, green: 0.88, blue: 1.0, alpha: 0.0).cgColor,
            NSColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.6).cgColor,
            NSColor(white: 1.0, alpha: 0.85).cgColor
        ] as CFArray
        
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 1.5, y: 0), end: CGPoint(x: 1.5, y: 40), options: [])
        }
        
        return ctx.makeImage()
    }
    
    private func createMatrixGlyphTexture() -> CGImage? {
        let size = CGSize(width: 14, height: 20)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        // Draw crisp code pill
        ctx.setFillColor(NSColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 0.9).cgColor)
        ctx.fill(CGRect(x: 3, y: 2, width: 8, height: 16))
        
        return ctx.makeImage()
    }
}
