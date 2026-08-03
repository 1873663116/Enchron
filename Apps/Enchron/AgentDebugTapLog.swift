import CoreGraphics
import Foundation
import OSLog

/// Session `2b511f` debug sink for playback surface-tap diagnosis.
/// Host XCUI reads `AppModel.debugSurfaceTapTrace` via control-plane value;
/// this helper also mirrors events to OSLog for GetConsoleOutput.
enum AgentDebugTapLog {
    static let sessionId = "2b511f"
    private static let logger = Logger(
        subsystem: "com.xiongzhipeng.XrPlayer",
        category: "DBG2b511f"
    )
    private static let lock = NSLock()
    private static var hitTestCount = 0

    static func event(
        _ message: String,
        hypothesisId: String,
        data: [String: Any] = [:],
        location: String
    ) {
        let payload: [String: Any] = [
            "sessionId": sessionId,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data
        ]
        let line: String
        if let json = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: json, encoding: .utf8) {
            line = text
        } else {
            line = "{\"sessionId\":\"\(sessionId)\",\"message\":\"\(message)\",\"hypothesisId\":\"\(hypothesisId)\"}"
        }
        logger.notice("DBG2b511f \(line, privacy: .public)")
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        let urls = candidateLogURLs()
        for url in urls {
            if FileManager.default.fileExists(atPath: url.path) == false {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { continue }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
        #endif
    }

    static func recordHitTest(bounds: CGRect, point: CGPoint, accepted: Bool) {
        lock.lock()
        hitTestCount += 1
        let count = hitTestCount
        lock.unlock()
        // Sample to avoid flooding while still proving hit delivery.
        guard count <= 3 || count % 40 == 0 else { return }
        event(
            "hitTest",
            hypothesisId: "B",
            data: [
                "count": count,
                "accepted": accepted,
                "bounds": "\(Int(bounds.width))x\(Int(bounds.height))",
                "point": "\(Int(point.x)),\(Int(point.y))"
            ],
            location: "PlaybackSurfaceTapPlane.swift:hitTest"
        )
    }

    private static func candidateLogURLs() -> [URL] {
        var urls: [URL] = []
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            urls.append(docs.appendingPathComponent("debug-2b511f.ndjson"))
        }
        // Workspace path is only writable when the process runs on the Mac host.
        urls.append(
            URL(fileURLWithPath: "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.cursor/debug-2b511f.log")
        )
        return urls
    }
}
