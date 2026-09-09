import Dispatch
import Foundation

/// The system's memory pressure level, held steady long enough to be acted on.
///
/// The kernel raises pressure and clears it again on its own schedule, and the lead budget
/// ramps back to its ceiling over `RendererLeadBudget.rampSeconds`. Following the raw signal
/// would let those two loops beat against each other every few seconds, which is visible as
/// the picture repeatedly building up and giving back its lead. So a raised level is held for
/// `releaseDwellSeconds` after the last elevated event before it is allowed to fall — the
/// hysteresis that the byte threshold this replaced never had.
public final class MemoryPressureMonitor: @unchecked Sendable {
    public static let shared = MemoryPressureMonitor()

    /// How long a raised level survives after the kernel stops reporting pressure.
    public static let releaseDwellSeconds: TimeInterval = 10

    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?
    private var reported: RendererLeadBudget.MemoryPressure = .normal
    private var elevatedUntil: Date?
    private var overrideLevel: RendererLeadBudget.MemoryPressure?

    private init() {}

    /// The level to budget against. Safe to call from any thread and on every delivery pass.
    public var current: RendererLeadBudget.MemoryPressure {
        lock.withLock {
            if let overrideLevel { return overrideLevel }
            startLocked()
            if let elevatedUntil, elevatedUntil > Date() { return reported }
            if elevatedUntil != nil {
                self.elevatedUntil = nil
                reported = .normal
            }
            return reported
        }
    }

    /// Pins the level for tests and for the device sweep, or returns to the live signal.
    public func setOverride(_ level: RendererLeadBudget.MemoryPressure?) {
        lock.withLock { overrideLevel = level }
    }

    private func startLocked() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .global(qos: .utility)
        )
        // The handler holds the source rather than reading `self.source`, which the lock
        // guards and this queue does not hold. The resulting cycle is deliberate: the
        // monitor is a process-lifetime singleton that never cancels its source.
        source.setEventHandler { [weak self] in
            self?.receive(source.data)
        }
        source.activate()
        self.source = source
    }

    private func receive(_ event: DispatchSource.MemoryPressureEvent) {
        let level: RendererLeadBudget.MemoryPressure
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            level = .normal
        }
        lock.withLock {
            guard level != .normal else { return }
            // A rise takes effect at once; the dwell only delays coming back down, and a
            // second event extends it rather than restarting from a lower step.
            if level == .critical || reported == .normal {
                reported = level
            }
            elevatedUntil = Date().addingTimeInterval(Self.releaseDwellSeconds)
        }
    }
}
