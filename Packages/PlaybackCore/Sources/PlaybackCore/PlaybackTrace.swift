import Foundation
import OSLog

public enum PlaybackTrace {
    private static let logger = Logger(
        subsystem: "com.xiongzhipeng.PlaybackCore",
        category: "PlaybackTrace"
    )

    public static func event(_ message: String) {
        logger.notice("[PBTRACE-7C31] \(message, privacy: .public)")
#if DEBUG
        sinkLock.withLock { sinkStorage }?(message)
#endif
    }

#if DEBUG
    private static let sinkLock = NSLock()
    nonisolated(unsafe) private static var sinkStorage: (@Sendable (String) -> Void)?

    public static func installSink(_ sink: (@Sendable (String) -> Void)?) {
        sinkLock.withLock { sinkStorage = sink }
    }
#endif

    public static func identity(_ object: AnyObject?) -> String {
        object.map { String(describing: ObjectIdentifier($0)) } ?? "none"
    }
}
