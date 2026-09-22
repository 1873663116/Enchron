import Dispatch
import Foundation

public final class MemoryPressureMonitor: @unchecked Sendable {
    public static let shared = MemoryPressureMonitor()

    public static let releaseDwellSeconds: TimeInterval = 10

    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?
    private var reported: RendererLeadBudget.MemoryPressure = .normal
    private var elevatedUntil: Date?

    private init() {}

    public var current: RendererLeadBudget.MemoryPressure {
        lock.withLock {
            startLocked()
            if let elevatedUntil, elevatedUntil > Date() { return reported }
            if elevatedUntil != nil {
                self.elevatedUntil = nil
                reported = .normal
            }
            return reported
        }
    }

    private func startLocked() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .global(qos: .utility)
        )
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
            if level == .critical || reported == .normal {
                reported = level
            }
            elevatedUntil = Date().addingTimeInterval(Self.releaseDwellSeconds)
        }
    }
}
