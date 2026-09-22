import Foundation
import OSLog

public enum PlaybackTrace {
    public static func event(_ message: @autoclosure () -> String) {
#if DEBUG
        let text = message()
        Logger(subsystem: "com.xiongzhipeng.PlaybackCore", category: "PlaybackTrace")
            .notice("[PBTRACE-7C31] \(text, privacy: .public)")
        sinkLock.withLock { sinkStorage }?(text)
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
