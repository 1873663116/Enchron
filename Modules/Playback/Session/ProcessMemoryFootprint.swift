import Darwin
import Foundation

enum ProcessMemoryFootprint {
    struct Reading: Equatable {
        var footprintBytes: UInt64
        var availableBytes: Int
        var mediaFootprintBytes: Int64?
        var mediaUnchargedBytes: Int64?
        var graphicsFootprintBytes: Int64?
        var graphicsUnchargedBytes: Int64?
        var compressedBytes: UInt64
        var swapInBytes: Int64?

        var limitBytes: UInt64 {
            footprintBytes + UInt64(max(availableBytes, 0))
        }
    }

    private static let ledgerRevisionCount: mach_msg_type_number_t = {
        fullFieldCount - 9
    }()

    private static let swapInRevisionCount: mach_msg_type_number_t = {
        fullFieldCount - 4
    }()

    private static let fullFieldCount = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )

    static func read() -> Reading? {
        var info = task_vm_info_data_t()
        var count = fullFieldCount
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let ledgerIsPopulated = count >= ledgerRevisionCount
        return Reading(
            footprintBytes: info.phys_footprint,
            availableBytes: os_proc_available_memory(),
            mediaFootprintBytes: ledgerIsPopulated ? info.ledger_tag_media_footprint : nil,
            mediaUnchargedBytes: ledgerIsPopulated ? info.ledger_tag_media_nofootprint : nil,
            graphicsFootprintBytes: ledgerIsPopulated ? info.ledger_tag_graphics_footprint : nil,
            graphicsUnchargedBytes: ledgerIsPopulated ? info.ledger_tag_graphics_nofootprint : nil,
            compressedBytes: info.compressed,
            swapInBytes: count >= swapInRevisionCount ? info.ledger_swapins : nil
        )
    }

    static var physicalFootprintBytes: UInt64? {
        read()?.footprintBytes
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
