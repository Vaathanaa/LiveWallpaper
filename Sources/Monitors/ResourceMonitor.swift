import AppKit
import Foundation
import IOKit.ps

@MainActor
public protocol ResourceMonitorDelegate: AnyObject {
    func resourceMonitorDidChangePauseState(activeReasons: Set<PauseReason>)
    func resourceMonitorDidTriggerIdleBufferRelease()
    func resourceMonitorDidDetectAppearanceChange()
    func resourceMonitorDidWakeOrUnlock()
    func resourceMonitorDidUpdatePowerProfile()
}

public extension ResourceMonitorDelegate {
    func resourceMonitorDidDetectAppearanceChange() {}
    func resourceMonitorDidWakeOrUnlock() {}
    func resourceMonitorDidUpdatePowerProfile() {}
}

@MainActor
public final class ResourceMonitor: NSObject, OcclusionDetectorDelegate {
    public weak var delegate: ResourceMonitorDelegate?
    
    public private(set) var activePauseReasons: Set<PauseReason> = []
    
    private let occlusionDetector = OcclusionDetector()
    private var idleBufferReleaseTimer: Timer?
    private var powerPollingTimer: Timer?
    
    private var isScreenLocked: Bool = false
    private var isScreenSaverActive: Bool = false
    private var isScreenAsleep: Bool = false
    private var isSystemAsleep: Bool = false
    
    public override init() {
        super.init()
        occlusionDetector.delegate = self
        setupNotificationObservers()
        startPowerPolling()
    }
    
    private func setupNotificationObservers() {
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            self,
            selector: #selector(screenLockedReceived),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(screenUnlockedReceived),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(screenSaverDidStartReceived),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(screenSaverDidStopReceived),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(themeChangedReceived),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(appChangedReceived),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(appChangedReceived),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(appChangedReceived),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(appChangedReceived),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(screensDidSleepReceived),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(screensDidWakeReceived),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(systemWillSleepReceived),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(systemDidWakeReceived),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(sessionDidChangeReceived),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(sessionDidChangeReceived),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChangedReceived),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChangedReceived),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    private func startPowerPolling() {
        powerPollingTimer?.invalidate()
        // Poll every 5 seconds (was 2.0s) — IOKit power source queries + CGSessionCopyCurrentDictionary
        // are expensive; 5s is sufficient since NSWorkspace notifications handle instant state changes.
        powerPollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.evaluateAllConditions()
                self.delegate?.resourceMonitorDidUpdatePowerProfile()
            }
        }
    }
    
    public func start() {
        occlusionDetector.start()
        evaluateAllConditions()
    }
    
    public func stop() {
        occlusionDetector.stop()
        idleBufferReleaseTimer?.invalidate()
        idleBufferReleaseTimer = nil
        powerPollingTimer?.invalidate()
        powerPollingTimer = nil
        
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func screenLockedReceived() {
        isScreenLocked = true
        evaluateAllConditions()
    }
    
    @objc private func screenUnlockedReceived() {
        isScreenLocked = false
        evaluateAllConditions()
        delegate?.resourceMonitorDidWakeOrUnlock()
    }
    
    @objc private func screenSaverDidStartReceived() {
        isScreenSaverActive = true
        evaluateAllConditions()
    }
    
    @objc private func screenSaverDidStopReceived() {
        isScreenSaverActive = false
        evaluateAllConditions()
    }
    
    @objc private func sessionDidChangeReceived() {
        evaluateAllConditions()
    }
    
    public static func isCurrentlyScreenLocked() -> Bool {
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if let isLocked = dict["CGSSessionScreenIsLocked"] as? Bool {
                return isLocked
            }
            if let isLockedNum = dict["CGSSessionScreenIsLocked"] as? Int {
                return isLockedNum != 0
            }
        }
        return false
    }
    
    @objc private func screensDidSleepReceived() {
        isScreenAsleep = true
        stopTimersForSleep()
        evaluateAllConditions()
        delegate?.resourceMonitorDidTriggerIdleBufferRelease()
    }
    
    @objc private func screensDidWakeReceived() {
        isScreenAsleep = false
        startTimersAfterWake()
        evaluateAllConditions()
        delegate?.resourceMonitorDidWakeOrUnlock()
    }
    
    @objc private func systemWillSleepReceived() {
        isSystemAsleep = true
        stopTimersForSleep()
        evaluateAllConditions()
        delegate?.resourceMonitorDidTriggerIdleBufferRelease()
    }
    
    @objc private func systemDidWakeReceived() {
        isSystemAsleep = false
        startTimersAfterWake()
        evaluateAllConditions()
        delegate?.resourceMonitorDidWakeOrUnlock()
    }
    
    @objc private func themeChangedReceived() {
        delegate?.resourceMonitorDidDetectAppearanceChange()
    }
    
    @objc private func appChangedReceived() {
        evaluateAllConditions()
    }
    
    public nonisolated static func isDarkMode() -> Bool {
        if let mode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle"), mode.caseInsensitiveCompare("Dark") == .orderedSame {
            return true
        }
        return false
    }
    
    private func stopTimersForSleep() {
        powerPollingTimer?.invalidate()
        powerPollingTimer = nil
        idleBufferReleaseTimer?.invalidate()
        idleBufferReleaseTimer = nil
        occlusionDetector.stop()
    }
    
    private func startTimersAfterWake() {
        startPowerPolling()
        occlusionDetector.start()
    }
    
    public static func isClamshellClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        if let prop = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
            return prop
        }
        if let num = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
            return num != 0
        }
        return false
    }
    
    @objc private func powerStateChangedReceived() {
        evaluateAllConditions()
        delegate?.resourceMonitorDidUpdatePowerProfile()
    }
    
    @objc private func thermalStateChangedReceived() {
        evaluateAllConditions()
        delegate?.resourceMonitorDidUpdatePowerProfile()
    }
    
    public func occlusionDetectorDidChangeState(occludedDisplays: Set<CGDirectDisplayID>) {
        evaluateAllConditions()
    }
    
    public static func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let state = description[kIOPSPowerSourceStateKey as String] as? String {
                if state == (kIOPSBatteryPowerValue as String) {
                    return true
                }
            }
        }
        return false
    }
    
    public static func getBatteryPercentage() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                if let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                   let max = description[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                    return Int((Double(current) / Double(max)) * 100)
                }
            }
        }
        return nil
    }
    
    public func evaluateAllConditions() {
        let settings = AppSettings.shared
        var reasons: Set<PauseReason> = []
        
        // Authoritative console check: if unlocked, clear isScreenLocked immediately
        if Self.isCurrentlyScreenLocked() {
            isScreenLocked = true
        } else {
            isScreenLocked = false
        }
        
        if settings.isUserPaused {
            reasons.insert(.userPaused)
        }
        if isScreenLocked {
            reasons.insert(.screenLocked)
        }
        if isScreenSaverActive {
            reasons.insert(.screenSaverActive)
        }
        if isScreenAsleep {
            reasons.insert(.screenAsleep)
        }
        if isSystemAsleep {
            reasons.insert(.systemAsleep)
        }
        if Self.isClamshellClosed() {
            reasons.insert(.clamshellClosed)
        }
        if settings.pauseOnBattery && Self.isOnBatteryPower() {
            reasons.insert(.onBattery)
        }
        if settings.pauseOnLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled {
            reasons.insert(.lowPowerMode)
        }
        if settings.pauseOnThermalThrottling {
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                reasons.insert(.thermalThrottling)
            }
        }
        
        // Multi-Display Intelligent Occlusion:
        // Only pause if ALL connected displays are fully occluded.
        // If an external monitor has a maximized window but the MacBook display is showing desktop,
        // we keep playing so the visible display stays lively!
        if settings.pauseWhenOccluded {
            let totalScreens = NSScreen.screens.count
            if occlusionDetector.occludedDisplays.count >= totalScreens && totalScreens > 0 {
                reasons.insert(.occluded(displayID: 0))
            }
        }
        
        // Feature 5: Smart Game & Heavy App Auto-Pause
        if settings.isHeavyAppPauseEnabled && !settings.heavyAppIdentifiers.isEmpty {
            let identifiers = Set(settings.heavyAppIdentifiers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
            
            if !identifiers.isEmpty {
                if settings.heavyAppPauseScope == .frontmostOnly {
                    if let frontApp = NSWorkspace.shared.frontmostApplication {
                        let bundleID = (frontApp.bundleIdentifier ?? "").lowercased()
                        let appName = (frontApp.localizedName ?? "").lowercased()
                        let execName = (frontApp.executableURL?.lastPathComponent ?? "").lowercased()
                        
                        let isMatch = identifiers.contains(bundleID) ||
                                      identifiers.contains(appName) ||
                                      identifiers.contains(execName) ||
                                      identifiers.contains(where: { !$0.isEmpty && (appName.contains($0) || bundleID.contains($0)) })
                        
                        if isMatch {
                            let displayName = frontApp.localizedName ?? frontApp.bundleIdentifier ?? "Heavy App"
                            reasons.insert(.heavyAppRunning(appName: displayName))
                        }
                    }
                } else {
                    for app in NSWorkspace.shared.runningApplications {
                        let bundleID = (app.bundleIdentifier ?? "").lowercased()
                        let appName = (app.localizedName ?? "").lowercased()
                        let execName = (app.executableURL?.lastPathComponent ?? "").lowercased()
                        
                        let isMatch = identifiers.contains(bundleID) ||
                                      identifiers.contains(appName) ||
                                      identifiers.contains(execName) ||
                                      identifiers.contains(where: { !$0.isEmpty && (appName.contains($0) || bundleID.contains($0)) })
                        
                        if isMatch {
                            let displayName = app.localizedName ?? app.bundleIdentifier ?? "Heavy App"
                            reasons.insert(.heavyAppRunning(appName: displayName))
                            break
                        }
                    }
                }
            }
        }
        
        let previousReasons = activePauseReasons
        activePauseReasons = reasons
        
        if previousReasons != reasons {
            delegate?.resourceMonitorDidChangePauseState(activeReasons: reasons)
            manageIdleBufferReleaseTimer(isPaused: !reasons.isEmpty)
        }
    }
    
    private func manageIdleBufferReleaseTimer(isPaused: Bool) {
        if isPaused {
            // Only schedule idle release for physical sleep or clamshell states,
            // never for user pause or normal app occlusion so the wallpaper stays frozen and visible.
            guard isScreenAsleep || isSystemAsleep || Self.isClamshellClosed() else {
                idleBufferReleaseTimer?.invalidate()
                idleBufferReleaseTimer = nil
                return
            }
            if idleBufferReleaseTimer == nil {
                let delay = AppSettings.shared.idleBufferReleaseSeconds
                idleBufferReleaseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.delegate?.resourceMonitorDidTriggerIdleBufferRelease()
                    }
                }
            }
        } else {
            idleBufferReleaseTimer?.invalidate()
            idleBufferReleaseTimer = nil
        }
    }
}
