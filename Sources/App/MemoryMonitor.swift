import Foundation
import Darwin.Mach

enum MemoryMonitor {
    static let jetsamEstimatedLimitBytes: UInt64 = 500 * 1024 * 1024

    /// Returns current app resident/footprint memory in bytes via Mach `task_vm_info`.
    static func currentFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return UInt64(info.phys_footprint)
        }
        return 0
    }

    static func currentFootprintMB() -> Double {
        return Double(currentFootprintBytes()) / (1024.0 * 1024.0)
    }

    static func totalPhysicalRAMMB() -> Double {
        return Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0)
    }

    static func formattedUsage() -> String {
        let usedMB = currentFootprintMB()
        let totalMB = totalPhysicalRAMMB()
        let limitMB = Double(jetsamEstimatedLimitBytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB / ~%.0f MB Jetsam (Máy: %.0f MB)", usedMB, limitMB, totalMB)
    }
}
