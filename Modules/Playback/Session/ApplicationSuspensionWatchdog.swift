import Foundation

public enum ApplicationSuspensionDetectionPolicy {
    public static let tickIntervalSeconds: TimeInterval = 2
    public static let minimumDetectedGapSeconds: TimeInterval = 10

    public static func detectedSuspension(gap: TimeInterval) -> Bool {
        gap >= minimumDetectedGapSeconds
    }
}

@MainActor
public final class ApplicationSuspensionWatchdog {
    private var tickTask: Task<Void, Never>?
    private var lastTickAt: Date?
    public var onResumeFromSuspension: (@MainActor (TimeInterval) -> Void)?

    public init() {}

    public func start() {
        guard tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = Date()
                if let lastTickAt = self.lastTickAt {
                    let gap = now.timeIntervalSince(lastTickAt)
                    if ApplicationSuspensionDetectionPolicy.detectedSuspension(gap: gap) {
                        self.onResumeFromSuspension?(gap)
                    }
                }
                self.lastTickAt = now
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        ApplicationSuspensionDetectionPolicy.tickIntervalSeconds
                            * 1_000_000_000
                    )
                )
            }
        }
    }
}
