import SwiftUI
import CoreImage
import AppKit

@MainActor
public final class WallpaperColorHarmony: ObservableObject {
    public static let shared = WallpaperColorHarmony()
    
    @Published public private(set) var primaryAccent: Color = .accentColor
    @Published public private(set) var secondaryAccent: Color = .secondary
    @Published public private(set) var primaryNSColor: NSColor = .controlAccentColor
    @Published public private(set) var hexString: String = "#007AFF"
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private init() {
        if let savedHex = UserDefaults.standard.string(forKey: "dynamicAccentColorHex"),
           let nsColor = NSColor(hex: savedHex) {
            updateColors(nsColor)
        }
    }
    
    public func extractPalette(from image: CGImage) {
        Task.detached(priority: .utility) {
            let ciImage = CIImage(cgImage: image)
            guard let filter = CIFilter(name: "CIAreaAverage") else { return }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
            
            guard let outputImage = filter.outputImage else { return }
            
            var bitmap = [UInt8](repeating: 0, count: 4)
            let context = CIContext(options: [.useSoftwareRenderer: false])
            context.render(
                outputImage,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            
            let r = CGFloat(bitmap[0]) / 255.0
            let g = CGFloat(bitmap[1]) / 255.0
            let b = CGFloat(bitmap[2]) / 255.0
            
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
