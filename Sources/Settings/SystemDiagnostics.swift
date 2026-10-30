import Foundation
import Darwin
import IOKit.ps
import Combine

@MainActor
public final class SystemDiagnostics: ObservableObject {
    public static let shared = SystemDiagnostics()
    
    @Published public var cpuPercentage: Double = 0.0
    @Published public var ramUsageMB: Double = 0.0
    @Published public var powerSource: String = "AC Power"
    @Published public var isLowPowerMode: Bool = false
    @Published public var thermalStateDescription: String = "Nominal"
    @Published public var activePauseReasons: [String] = []
    
    private var updateTimer: Timer?
    
    public static var chipModelName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let name = String(cString: brand).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Apple Silicon" : name
    }
    
    private init() {
        // Idling by default. Timers run only when Settings panel is displayed.
    }
    
    public func startMonitoring() {
        stopMonitoring()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.refresh()
            }
        }
        refresh()
    }
    
    public func stopMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    public func refresh() {
        self.cpuPercentage = measureCPU()
        self.ramUsageMB = measureRAM()
        self.powerSource = ResourceMonitor.isOnBatteryPower() ? "Battery" : "Power Adapter (AC)"
        self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: self.thermalStateDescription = "Nominal (Cool)"
        case .fair: self.thermalStateDescription = "Fair (Normal)"
        case .serious: self.thermalStateDescription = "Serious (Throttling)"
        case .critical: self.thermalStateDescription = "Critical (High Heat)"
        @unknown default: self.thermalStateDescription = "Unknown"
        }
        
        let coordinator = PlaybackCoordinator.shared
        self.activePauseReasons = coordinator.resourceMonitor.activePauseReasons.map { $0.description }
    }
    
    private func measureRAM() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        return 0.0
    }
    
    private func measureCPU() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let kerr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kerr == KERN_SUCCESS, let threads = threadList else { return 0.0 }
        
        var totalUsage: Double = 0.0
        for i in 0..<Int(threadCount) {
            let thread = threads[i]
            var threadInfo = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let threadKerr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    Darwin.thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if threadKerr == KERN_SUCCESS {
                if (threadInfo.flags & TH_FLAGS_IDLE) == 0 {
                    totalUsage += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
            // Deallocate each thread send right to prevent Mach port exhaustion
            mach_port_deallocate(mach_task_self_, thread)
        }
        vm_deallocate(
            mach_task_self_,
            vm_address_t(UInt(bitPattern: threads)),
            vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size)
        )
        return totalUsage
    }
}
