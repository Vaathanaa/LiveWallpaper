import SwiftUI
import CoreGraphics
import AppKit

@MainActor
public final class WallpaperColorHarmony: ObservableObject {
    public static let shared = WallpaperColorHarmony()
    
    @Published public private(set) var primaryAccent: Color = .accentColor
    @Published public private(set) var secondaryAccent: Color = .secondary
    @Published public private(set) var primaryNSColor: NSColor = .controlAccentColor
    @Published public private(set) var hexString: String = "#007AFF"
    
    private init() {
        if let savedHex = UserDefaults.standard.string(forKey: "dynamicAccentColorHex"),
           let nsColor = NSColor(hex: savedHex) {
            updateColors(nsColor)
        }
    }
    
    public func extractPalette(from image: CGImage) {
        Task.detached(priority: .utility) {
            // Downsample to a lightweight 64x36 thumbnail for instantaneous 0.05ms color sampling
            // Bypasses heavy CoreImage Metal context allocations completely
            let thumbWidth = 64
            let thumbHeight = 36
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixelData = [UInt8](repeating: 0, count: thumbWidth * thumbHeight * 4)
            guard let context = CGContext(
                data: &pixelData,
                width: thumbWidth,
                height: thumbHeight,
                bitsPerComponent: 8,
                bytesPerRow: thumbWidth * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
            
            var totalR: UInt64 = 0
            var totalG: UInt64 = 0
            var totalB: UInt64 = 0
            let totalPixels = thumbWidth * thumbHeight
            
            for i in stride(from: 0, to: pixelData.count, by: 4) {
                totalR += UInt64(pixelData[i])
                totalG += UInt64(pixelData[i + 1])
                totalB += UInt64(pixelData[i + 2])
            }
            
            let r = CGFloat(totalR / UInt64(totalPixels)) / 255.0
            let g = CGFloat(totalG / UInt64(totalPixels)) / 255.0
            let b = CGFloat(totalB / UInt64(totalPixels)) / 255.0
            
            // Convert to HSB to ensure dynamic accent has healthy vibrance and visibility
            let nsColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bri: CGFloat = 0
            var alpha: CGFloat = 0
            nsColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            
            // Clamp vibrance for optimal macOS glassmorphic contrast
            let tunedSat = max(0.45, min(0.95, sat * 1.3))
            let tunedBri = max(0.55, min(0.98, bri))
            let tunedColor = NSColor(hue: hue, saturation: tunedSat, brightness: tunedBri, alpha: 1.0)
            
            await MainActor.run {
                self.updateColors(tunedColor)
            }
        }
    }
    
    private func updateColors(_ color: NSColor) {
        self.primaryNSColor = color
        self.primaryAccent = Color(nsColor: color)
        self.secondaryAccent = Color(nsColor: color.withAlphaComponent(0.65))
        
        let hex = color.toHex()
        self.hexString = hex
        AppSettings.shared.dynamicAccentColorHex = hex
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let intVal = UInt64(cleanHex, radix: 16) else { return nil }
        
        let r = CGFloat((intVal >> 16) & 0xFF) / 255.0
        let g = CGFloat((intVal >> 8) & 0xFF) / 255.0
        let b = CGFloat(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    func toHex() -> String {
        guard let rgb = self.usingColorSpace(.deviceRGB) else { return "#007AFF" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
