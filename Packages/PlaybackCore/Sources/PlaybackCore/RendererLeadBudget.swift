@preconcurrency import AVFoundation
import Darwin
import Foundation

public enum RendererLeadBudget {
    /// How much memory the system says it is short of, which is the only external reason to
    /// give delivery frames back.
    ///
    /// The process's own remaining allowance is deliberately *not* an input. That figure is
    /// the limit minus our footprint, and the limit does not shrink because other processes
    /// got busy — so a falling allowance is our own growth, and starving the picture in
    /// response would hide the leak rather than address it. The allowance drives an alarm
    /// and a cache release elsewhere; only system pressure moves this ladder.
    public enum MemoryPressure: Sendable, Equatable {
        case normal
        case warning
        case critical
    }

    static let schedulingSlackFrames = 2

    static let minimumOutputLagFrames = 2

    static let localMaximumFrames = environmentInteger("ENCHRON_RENDERER_LEAD_MAX_FRAMES") ?? 32

    static let remoteMaximumFrames = environmentInteger("ENCHRON_RENDERER_LEAD_MAX_FRAMES") ?? 48

    static let rampSeconds = 1.5

    /// The first concession, and a free one. 24 frames and 32 measure the same displayed
    /// rate: 4K60 ten-bit gave 45–52 against 48–51 on 2026-09-08, and 2026-09-09 read 46.6
    /// and 44.0 at 24 against 45.6 and 43.6 at 32 on an 8K stereo clip — indistinguishable
    /// across two runs and within one.
    static let warningCeilingFrames = 24

    /// The bottom of the ladder, and the whole of it. This step is not free — 8K measured
    /// 34.8 displayed frames per second here against 46.6 at 24 — but it is far above the
    /// reorder floor the previous rule fell to, which read 21 on the same footage. Below
    /// this the picture is starved to save tens of megabytes, and a footprint that keeps
    /// climbing past here is our own leak that a starved picture would only hide.
    static let criticalCeilingFrames = 16

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

    /// The ceiling the ramp climbs toward under a given pressure.
    ///
    /// Each step is clamped up to `floorFrames`: the reorder floor is a correctness bound —
    /// below it a paused seek never settles on its target — so a stream with a deep reorder
    /// depth keeps the frames it needs no matter how short of memory the system is.
    static func ceilingFrames(
        reorderDepth: Int,
        isRemoteSource: Bool,
        memoryPressure: MemoryPressure
    ) -> Int {
        let floor = floorFrames(reorderDepth: reorderDepth)
        let sourceCeiling = max(floor, maximumFrames(isRemoteSource: isRemoteSource))
        let step: Int
        switch memoryPressure {
        case .normal: step = sourceCeiling
        case .warning: step = max(warningCeilingFrames, floor)
        case .critical: step = max(criticalCeilingFrames, floor)
        }
        return min(sourceCeiling, step)
    }

    static func frames(
        reorderDepth: Int,
        isRemoteSource: Bool,
        secondsSinceDeliveryStart: Double?,
        memoryPressure: MemoryPressure
    ) -> Int {
        if let fixed = currentFixedFramesOverride {
            return fixed
        }
        let floor = floorFrames(reorderDepth: reorderDepth)
        let ceiling = ceilingFrames(
            reorderDepth: reorderDepth,
            isRemoteSource: isRemoteSource,
            memoryPressure: memoryPressure
        )
        // The ramp still starts at the reorder floor whatever the pressure: it exists so a
        // dragged scrub holds few frames in flight and pays a cheap flush per seek, which is
        // unrelated to how much memory is left.
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
