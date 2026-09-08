import Darwin
import Foundation

enum ProcessMemoryFootprint {
    static var physicalFootprintBytes: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    static var availableBytes: Int {
        os_proc_available_memory()
    }

    static var probeFields: [String] {
        [
            "footprintMB=\(physicalFootprintBytes.map { String($0 / 1_048_576) } ?? "none")",
            "availableMB=\(availableBytes / 1_048_576)"
        ]
    }
}
