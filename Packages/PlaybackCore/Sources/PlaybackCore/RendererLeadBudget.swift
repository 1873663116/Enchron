@preconcurrency import AVFoundation
import Foundation

enum RendererLeadBudget {
    static let schedulingSlackFrames = 2

    static let maximumFrames = environmentInteger("ENCHRON_RENDERER_LEAD_MAX_FRAMES") ?? 48

    static let maximumDecodedBytes = environmentDouble("ENCHRON_RENDERER_LEAD_MAX_BYTES")
        ?? (200.0 * 1024.0 * 1024.0)

    static func frames(
        reorderDepth: Int,
        encodedWidth: Int,
        encodedHeight: Int,
        decodedBytesPerPixel: Double
    ) -> Int {
        let floor = max(0, reorderDepth) + schedulingSlackFrames
        let bytesPerFrame = Double(encodedWidth)
            * Double(encodedHeight)
            * decodedBytesPerPixel
        guard bytesPerFrame > 0, bytesPerFrame.isFinite else {
            return max(floor, maximumFrames)
        }
        let affordable = (maximumDecodedBytes / bytesPerFrame).rounded(.down)
        guard affordable < Double(maximumFrames) else {
            return max(floor, maximumFrames)
        }
        return max(floor, min(maximumFrames, Int(affordable)))
    }

    private static func environmentInteger(_ name: String) -> Int? {
        guard let raw = ProcessInfo.processInfo.environment[name],
              let value = Int(raw), value > 0 else { return nil }
        return value
    }

    private static func environmentDouble(_ name: String) -> Double? {
        guard let raw = ProcessInfo.processInfo.environment[name],
              let value = Double(raw), value.isFinite, value > 0 else { return nil }
        return value
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

    mutating func nextRetirement(after timelineSeconds: Double) -> Double? {
        presentationEnds.removeAll { $0 <= timelineSeconds }
        return presentationEnds.min()
    }

    mutating func removeAll() {
        presentationEnds.removeAll()
    }
}
