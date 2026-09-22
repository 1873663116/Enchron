#if DEBUG
import Darwin
import Foundation

nonisolated enum ProcessMemoryRegions {
    struct Summary: Equatable, Sendable {
        var residentBytesByTag: [UInt32: UInt64]
        var dirtyBytesByTag: [UInt32: UInt64]
        var regionCount: Int

        func resident(_ tags: Set<UInt32>) -> UInt64 {
            tags.reduce(0) { $0 + (residentBytesByTag[$1] ?? 0) }
        }

        func dirty(_ tags: Set<UInt32>) -> UInt64 {
            tags.reduce(0) { $0 + (dirtyBytesByTag[$1] ?? 0) }
        }
    }

    static let ioKitTag: UInt32 = 21
    static let ioSurfaceTag: UInt32 = 88
    static let videoBitstreamTag: UInt32 = 91
    static let ioAcceleratorTag: UInt32 = 100
    static let coreMediaTags: Set<UInt32> = [92, 93, 94, 95, 96, 101, 106]
    static let mallocTags: Set<UInt32> = Set(1...13)

    @MainActor static var lastSummary: Summary?

    private static let infoCount = mach_msg_type_number_t(
        MemoryLayout<vm_region_submap_info_data_64_t>.size / MemoryLayout<natural_t>.size
    )

    private static var pageSize: UInt64 {
        var size: vm_size_t = 0
        guard host_page_size(mach_host_self(), &size) == KERN_SUCCESS else { return 0 }
        return UInt64(size)
    }

    static func read() -> Summary? {
        walk()
    }

    private static func walk() -> Summary? {
        var summary = Summary(
            residentBytesByTag: [:],
            dirtyBytesByTag: [:],
            regionCount: 0
        )
        var address: vm_address_t = 0
        let pageSize = pageSize
        guard pageSize > 0 else { return nil }

        let maxDepth: natural_t = 32
        let maxRegions = 1 << 22
        var depth: natural_t = 0
        while summary.regionCount < maxRegions {
            var size: vm_size_t = 0
            var info = vm_region_submap_info_data_64_t()

            while true {
                var count = infoCount
                let result = withUnsafeMutablePointer(to: &info) { pointer in
                    pointer.withMemoryRebound(
                        to: integer_t.self,
                        capacity: Int(infoCount)
                    ) { reboundPointer in
                        vm_region_recurse_64(
                            mach_task_self_,
                            &address,
                            &size,
                            &depth,
                            reboundPointer,
                            &count
                        )
                    }
                }
                guard result == KERN_SUCCESS else {
                    return summary.regionCount > 0 ? summary : nil
                }
                guard info.is_submap != 0, depth < maxDepth else { break }
                depth += 1
            }

            let tag = info.user_tag
            summary.residentBytesByTag[tag, default: 0] += UInt64(info.pages_resident) * pageSize
            summary.dirtyBytesByTag[tag, default: 0] += UInt64(info.pages_dirtied) * pageSize
            summary.regionCount += 1

            guard size > 0 else { break }
            let next = address &+ size
            guard next > address else { break }
            address = next
        }

        return summary.regionCount > 0 ? summary : nil
    }
}
#endif
