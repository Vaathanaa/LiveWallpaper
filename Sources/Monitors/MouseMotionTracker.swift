import AppKit
import QuartzCore
import Combine

@MainActor
public protocol MouseMotionTrackerDelegate: AnyObject {
    func mouseMotionTrackerDidTick(globalLocation: CGPoint, dt: Double) -> Bool
}

// Hardware DisplayLink wrapper isolated for macOS 14+
@available(macOS 14.0, *)
private final class DisplayLinkDriver {
    let link: CADisplayLink
    init(target: AnyObject, selector: Selector, screen: NSScreen) {
        let link = screen.displayLink(target: target, selector: selector)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }
    func invalidate() {
        link.invalidate()
    }
    var isPaused: Bool {
        get { link.isPaused }
        set { link.isPaused = newValue }
    }
}

@MainActor
public final class MouseMotionTracker: NSObject, ObservableObject {
    public static let shared = MouseMotionTracker()
    
    public weak var delegate: MouseMotionTrackerDelegate?
    
    private var globalMonitor: Any?
    private var isTracking: Bool = false
    
    @Published public private(set) var currentPoint: CGPoint = .zero
    
    // Hardware DisplayLink locked to ProMotion 120Hz refresh (macOS 14+) with timer fallback (macOS 13)
    private var displayLinkDriver: Any?
    private var fallbackTimer: Timer?
    private var lastFrameTimestamp: CFTimeInterval = 0.0
    private var lastMouseMoveTimestamp: CFTimeInterval = 0.0
    private var isResting: Bool = false
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func screenParametersChanged() {
        guard isTracking else { return }
        setupHardwareDisplayLink()
        wakeDisplayLink()
    }
    
    public func start() {
        guard !isTracking else { return }
        isTracking = true
        
        currentPoint = NSEvent.mouseLocation
        lastMouseMoveTimestamp = CACurrentMediaTime()
        
        // Passive global mouse tracking: zero permissions needed, zero click interception
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(location: NSEvent.mouseLocation)
            }
        }
        
        setupHardwareDisplayLink()
        wakeDisplayLink()
    }
    
    public func stop() {
        guard isTracking else { return }
        isTracking = false
        
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        tearDownDisplayLink()
        isResting = true
    }
    
    // MARK: - Hardware ProMotion Display Link
    
    private func setupHardwareDisplayLink() {
        tearDownDisplayLink()
        
        if #available(macOS 14.0, *), let screen = NSScreen.main ?? NSScreen.screens.first {
            self.displayLinkDriver = DisplayLinkDriver(target: self, selector: #selector(onDisplayLinkTick(_:)), screen: screen)
        } else {
            // High-precision fallback timer
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.tickDisplayLink(dt: 1.0 / 120.0)
                }
            }
        }
        lastFrameTimestamp = CACurrentMediaTime()
    }
    
    private func tearDownDisplayLink() {
        if #available(macOS 14.0, *), let driver = displayLinkDriver as? DisplayLinkDriver {
            driver.invalidate()
        }
        displayLinkDriver = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }
    
    public func wakeDisplayLink() {
        isResting = false
        if #available(macOS 14.0, *), let driver = displayLinkDriver as? DisplayLinkDriver, driver.isPaused {
            lastFrameTimestamp = CACurrentMediaTime()
            driver.isPaused = false
        }
    }
    
    public func sleepDisplayLink() {
        isResting = true
        if #available(macOS 14.0, *), let driver = displayLinkDriver as? DisplayLinkDriver {
            driver.isPaused = true
        }
    }
    
    // MARK: - Input Handling
    
    private func handleMouseMoved(location: CGPoint) {
        currentPoint = location
        lastMouseMoveTimestamp = CACurrentMediaTime()
        wakeDisplayLink()
    }
    
    // MARK: - Display Link Tick
    
    @objc private func onDisplayLinkTick(_ sender: AnyObject) {
        var dt = 1.0 / 120.0
        if #available(macOS 14.0, *), let link = sender as? CADisplayLink {
            let now = link.timestamp > 0 ? link.timestamp : CACurrentMediaTime()
            dt = now - lastFrameTimestamp
            lastFrameTimestamp = now
        } else {
            let now = CACurrentMediaTime()
            dt = now - lastFrameTimestamp
            lastFrameTimestamp = now
        }
        
        if dt <= 0.0 || dt > 0.05 {
            dt = 1.0 / 120.0
        }
        
        tickDisplayLink(dt: dt)
    }
    
    private func tickDisplayLink(dt: Double) {
        guard AppSettings.shared.isMouseInteractionEnabled else {
            _ = delegate?.mouseMotionTrackerDidTick(globalLocation: currentPoint, dt: dt)
            sleepDisplayLink()
            return
        }
        
        let allResting = delegate?.mouseMotionTrackerDidTick(globalLocation: currentPoint, dt: dt) ?? true
        
        // Sleep displaylink when mouse has stopped and all animations have settled
        let now = CACurrentMediaTime()
        if allResting && (now - lastMouseMoveTimestamp > 0.6) {
            sleepDisplayLink()
        }
    }
}
