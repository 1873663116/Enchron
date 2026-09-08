@preconcurrency import AVFoundation
import Darwin
import Foundation

public enum RendererLeadBudget {
    static let schedulingSlackFrames = 2

    static let minimumOutputLagFrames = 2

    static let localMaximumFrames = environmentInteger("ENCHRON_RENDERER_LEAD_MAX_FRAMES") ?? 32

    static let remoteMaximumFrames = environmentInteger("ENCHRON_RENDERER_LEAD_MAX_FRAMES") ?? 48

    static let rampSeconds = 1.5

    static let lowMemoryFloorBytes = 512 * 1024 * 1024

    private static let overrideLock = NSLock()
    nonisolated(unsafe) private static var fixedFramesOverride: Int?

    public static func setFixedFramesOverride(_ frames: Int?) {
        overrideLock.withLock { fixedFramesOverride = frames.map { max(1, $0) } }
    }

    public static var currentFixedFramesOverride: Int? {
        overrideLock.withLock { fixedFramesOverride }
    }

    static func outputLagFrames(reorderDepth: Int) -> Int {
        max(reorderDepth, minimumOutputLagFrames)
    }

    static func floorFrames(reorderDepth: Int) -> Int {
        outputLagFrames(reorderDepth: reorderDepth) + schedulingSlackFrames
    }

    static func maximumFrames(isRemoteSource: Bool) -> Int {
        isRemoteSource ? remoteMaximumFrames : localMaximumFrames
    }

    static func frames(
        reorderDepth: Int,
        isRemoteSource: Bool,
        secondsSinceDeliveryStart: Double?,
        availableMemoryBytes: Int
    ) -> Int {
        if let fixed = currentFixedFramesOverride {
            return fixed
        }
        let floor = floorFrames(reorderDepth: reorderDepth)
        let ceiling = max(floor, maximumFrames(isRemoteSource: isRemoteSource))
        guard availableMemoryBytes >= lowMemoryFloorBytes else { return floor }
        guard let elapsed = secondsSinceDeliveryStart, elapsed.isFinite, elapsed > 0 else {
            return floor
        }
        let progress = min(1, elapsed / rampSeconds)
        return floor + Int((Double(ceiling - floor) * progress).rounded(.down))
    }

    private static func environmentInteger(_ name: String) -> Int? {
        guard let raw = ProcessInfo.processInfo.environment[name],
              let value = Int(raw), value > 0 else { return nil }
        return value
    }
}

enum ProcessMemory {
    static var availableBytes: Int {
        #if os(iOS) || os(visionOS) || os(tvOS)
        os_proc_available_memory()
        #else
        Int.max
        #endif
    }
}

struct RendererFramesInFlight {
    private var presentationEnds: [Double] = []

    mutating func record(presentationEnd: Double) {
        guard presentationEnd.isFinite else { return }
        presentationEnds.append(presentationEnd)
    }

    mutating func count(timelineSeconds: Double) -> Int {
        presentationEnds.removeAll { $0 <= timelineSeconds }
        return presentationEnds.count
    }

    func earliestRetirement() -> Double? {
        presentationEnds.min()
    }

    mutating func removeAll() {
        presentationEnds.removeAll()
    }
}
