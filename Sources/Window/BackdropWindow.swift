import AppKit
import CoreGraphics

public final class BackdropWindow: NSWindow {
    
    public let displayID: CGDirectDisplayID
    
    public init(screen: NSScreen, levelMode: WindowLevelMode) {
        self.displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = false
        self.hasShadow = false
        self.isOpaque = true
        self.backgroundColor = .black
        self.ignoresMouseEvents = true
        self.canHide = false
        self.isExcludedFromWindowsMenu = true
        self.sharingType = .readOnly
        
        // Critical for 120Hz ProMotion smoothness during "Show Desktop" and Mission Control
        self.animationBehavior = .none
        
        // Adopt the exact native color space of the screen (Display P3 for XDR, sRGB/Rec709 for externals)
        if let cs = screen.colorSpace {
            self.colorSpace = cs
        }
        
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        
        updateWindowLevel(levelMode)
        self.setFrame(screen.frame, display: true)
    }
    
    public func updateWindowLevel(_ mode: WindowLevelMode) {
        switch mode {
        case .desktop:
            // kCGDesktopWindowLevel + 1 (-2147483622):
            // Sits directly on top of the root desktop wallpaper canvas (-2147483624) and below desktop icons (-2147483603).
            // Recognized by macOS WindowServer as native desktop background, enabling hardware
            // direct scanout and butter-smooth 120Hz ProMotion gesture animations during
            // Mission Control, App Exposé, and "Show Desktop".
            self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        case .belowIcons:
            // Level -2147483604: Sits directly behind desktop icons and widgets (-2147483603)
            self.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        }
    }
    
    public func updateFrame(for screen: NSScreen) {
        self.setFrame(screen.frame, display: true)
        if let cs = screen.colorSpace {
            self.colorSpace = cs
        }
    }
    
    public override var canBecomeKey: Bool { return false }
    public override var canBecomeMain: Bool { return false }
}
