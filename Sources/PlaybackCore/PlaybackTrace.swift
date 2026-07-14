import Foundation
import OSLog

public enum PlaybackTrace {
    private static let logger = Logger(
        subsystem: "com.xiongzhipeng.PlaybackLab",
        category: "VisionPlaybackTrace"
    )

    public static func event(_ message: String) {
        logger.notice("[PBTRACE-7C31] \(message, privacy: .public)")
    }

    public static func identity(_ object: AnyObject?) -> String {
        object.map { String(describing: ObjectIdentifier($0)) } ?? "none"
    }
}
