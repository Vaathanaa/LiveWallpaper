import Foundation
import CoreGraphics

public enum PauseReason: Hashable, CustomStringConvertible, Sendable {
    case userPaused
    case screenLocked
    case screenSaverActive
    case screenAsleep
    case systemAsleep
    case clamshellClosed
    case onBattery
    case lowPowerMode
    case thermalThrottling
    case occluded(displayID: CGDirectDisplayID)
    case heavyAppRunning(appName: String)
    
    public var description: String {
        switch self {
        case .userPaused:
            return "Paused by User"
        case .screenLocked:
            return "Screen Locked"
        case .screenSaverActive:
            return "Screen Saver Active"
        case .screenAsleep:
            return "Display Asleep"
        case .systemAsleep:
            return "Mac Sleeping"
        case .clamshellClosed:
            return "Lid Closed / Display Off"
        case .onBattery:
            return "Running on Battery"
        case .lowPowerMode:
            return "Low Power Mode Enabled"
        case .thermalThrottling:
            return "Thermal Throttling Active"
        case .occluded(let id):
            return "Display \(id) Fully Covered / Fullscreen"
        case .heavyAppRunning(let appName):
            return "Resource-Intensive App Active (\(appName))"
        }
    }
}
