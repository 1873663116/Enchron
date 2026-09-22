#if DEBUG
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
        var internalBytes: UInt64
        var externalBytes: UInt64
        var purgeableNonvolatileBytes: Int64?

        var limitBytes: UInt64 {
            footprintBytes + UInt64(max(availableBytes, 0))
        }

        var untaggedResidualBytes: Int64 {
            Int64(footprintBytes)
                - Int64(internalBytes)
                - Int64(compressedBytes)
                - max(purgeableNonvolatileBytes ?? 0, 0)
                - max(mediaFootprintBytes ?? 0, 0)
                - max(graphicsFootprintBytes ?? 0, 0)
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
            swapInBytes: count >= swapInRevisionCount ? info.ledger_swapins : nil,
            internalBytes: info.internal,
            externalBytes: info.external,
            purgeableNonvolatileBytes: ledgerIsPopulated ? info.ledger_purgeable_nonvolatile : nil
        )
    }

    static var physicalFootprintBytes: UInt64? {
        read()?.footprintBytes
    }

    static var availableBytes: Int {
        os_proc_available_memory()
    }

    static var probeFields: [String] {
        let reading = read()
        return [
            "footprintMB=\(reading.map { String($0.footprintBytes / 1_048_576) } ?? "none")",
            "availableMB=\(availableBytes / 1_048_576)",
            "internalMB=\(reading.map { String($0.internalBytes / 1_048_576) } ?? "none")",
            "compressedMB=\(reading.map { String($0.compressedBytes / 1_048_576) } ?? "none")",
            "residualMB=\(reading.map { String($0.untaggedResidualBytes / 1_048_576) } ?? "none")",
            "mediaMB=\(reading?.mediaFootprintBytes.map { String($0 / 1_048_576) } ?? "none")",
            "graphicsMB=\(reading?.graphicsFootprintBytes.map { String($0 / 1_048_576) } ?? "none")",
            "iosfMB=\(ProcessMemoryRegions.lastSummary.map { String($0.resident([ProcessMemoryRegions.ioSurfaceTag]) / 1_048_576) } ?? "none")",
            "ioacMB=\(ProcessMemoryRegions.lastSummary.map { String($0.resident([ProcessMemoryRegions.ioAcceleratorTag]) / 1_048_576) } ?? "none")",
            "cmMB=\(ProcessMemoryRegions.lastSummary.map { String($0.resident(ProcessMemoryRegions.coreMediaTags) / 1_048_576) } ?? "none")",
            "vbsMB=\(ProcessMemoryRegions.lastSummary.map { String($0.resident([ProcessMemoryRegions.videoBitstreamTag]) / 1_048_576) } ?? "none")"
        ]
    }
}
#endif
