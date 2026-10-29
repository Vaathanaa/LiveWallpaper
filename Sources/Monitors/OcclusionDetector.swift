import AppKit
import CoreGraphics

@MainActor
public protocol OcclusionDetectorDelegate: AnyObject {
    func occlusionDetectorDidChangeState(occludedDisplays: Set<CGDirectDisplayID>)
}

@MainActor
public final class OcclusionDetector {
    public weak var delegate: OcclusionDetectorDelegate?
    
    private var checkTimer: Timer?
    private var debounceTimer: Timer?
    private var isEnabled: Bool = true
    public private(set) var occludedDisplays: Set<CGDirectDisplayID> = []
    
    public init() {
        setupObservers()
    }
    
    public func start() {
        stop()
        // Slow periodic check (every 3 seconds)
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateOcclusion()
            }
        }
        scheduleEvaluation(delay: 0.5)
    }
    
    public func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
        occludedDisplays.removeAll()
    }
    
    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
            delegate?.occlusionDetectorDidChangeState(occludedDisplays: [])
        }
    }
    
    private func setupObservers() {
        // Debounce workspace transitions so "Show Desktop", Mission Control, and 3-finger Spaces gestures remain silky smooth
        // Allowing 0.9s delay ensures WindowServer's interactive gesture animations have 100% finished before querying window info
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEvaluation(delay: 0.9)
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleEvaluation(delay: 0.9)
            }
        }
    }
    
    private func scheduleEvaluation(delay: TimeInterval) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateOcclusion()
            }
        }
    }
    
    public func evaluateOcclusion() {
        guard isEnabled else { return }
        
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return
        }
        
        let screens = NSScreen.screens
        guard let primaryScreen = screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        
        var newOccluded: Set<CGDirectDisplayID> = []
        
        for screen in screens {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            
            let cgY = primaryHeight - (screen.frame.origin.y + screen.frame.height)
            let screenCGBounds = CGRect(
                x: screen.frame.origin.x,
                y: cgY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            let screenArea = screenCGBounds.width * screenCGBounds.height
            
            var isCovered = false
            for windowInfo in windowList {
                guard let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == 0,
                      let alpha = windowInfo[kCGWindowAlpha as String] as? Double, alpha > 0.95,
                      let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: Any],
                      let wBounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                    continue
                }
                
                let owner = windowInfo[kCGWindowOwnerName as String] as? String ?? ""
                let ignoredSystemOwners: Set<String> = [
                    "Window Server", "Dock", "Wallpaper", "Finder",
                    "screencaptureui", "screencapture", "Screenshot",
                    "QuickTime Player", "ControlCenter", "SystemUIServer",
                    "NotificationCenter", "VideoBackdrop"
                ]
                if ignoredSystemOwners.contains(owner) {
                    continue
                }
                
                let intersection = screenCGBounds.intersection(wBounds)
                guard !intersection.isNull, !intersection.isEmpty else {
                    continue
                }
                let intersectArea = intersection.width * intersection.height
                
                if intersectArea >= (screenArea * 0.98) {
                    isCovered = true
                    break
                }
            }
            
            if isCovered {
                newOccluded.insert(displayID)
            }
        }
        
        if newOccluded != occludedDisplays {
            occludedDisplays = newOccluded
            delegate?.occlusionDetectorDidChangeState(occludedDisplays: newOccluded)
        }
    }
}
