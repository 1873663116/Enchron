#if DEBUG
import Foundation
import OSLog

public enum MediaFirstFrameProbe {
    private static let logger = Logger(subsystem: "app.enchron", category: "Playback")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var reported = false
    nonisolated(unsafe) private static var commandStartedAt: Date?

    public static func report(displayedFrames: Int?) {
        guard let displayedFrames, displayedFrames > 0 else { return }
        let shouldReport = lock.withLock { () -> Bool in
            guard !reported else { return false }
            reported = true
            return true
        }
        guard shouldReport else { return }
        let elapsed = commandStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
        logger.info(
            """
            playback.firstFrame frames=\(displayedFrames, privacy: .public) \
            ms=\(elapsed ?? -1, privacy: .public) at=\(Date().timeIntervalSince1970, privacy: .public)
            """
        )
    }

    public static func markCommand() {
        let now = Date()
        lock.withLock {
            reported = false
            commandStartedAt = now
        }
        logger.info("playback.command at=\(now.timeIntervalSince1970, privacy: .public)")
    }

    public static func reset() {
        lock.withLock {
            reported = false
            commandStartedAt = nil
        }
    }
}
#endif
