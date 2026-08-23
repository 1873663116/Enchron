@preconcurrency import AVFoundation
import Foundation

/// How far ahead of the timeline the delivery loop may run, counted in the
/// decoded frames the video renderer is holding.
///
/// Media seconds were the wrong unit. A seek waits on the renderer's flush, and
/// that cost tracks the number of decoded frames and their size, not their
/// duration. The 2026-08-22 Vision Pro sweep on an 8192x4096 59.94 fps stream
/// measured flush time growing as frames^1.8, so two streams holding the same
/// lead in seconds are two orders of magnitude apart in what a seek pays for it.
///
/// No mature decoder-side implementation bounds this in seconds. VLC paces
/// VideoToolbox by field count against the encoded reorder depth, Chromium caps
/// concurrent decode requests at four, and mpv's optional decoded queue trips on
/// frames or bytes before its two-second limit.
enum RendererLeadBudget {
    /// Frames the delivery loop may hold beyond the encoder's reorder delay. One
    /// is the frame the renderer is displaying; the second covers the provider
    /// read, which runs on the same task and so stalls delivery for its whole
    /// duration. At one the renderer runs dry whenever a read outlasts a frame
    /// period, which a remote source does routinely.
    static let schedulingSlackFrames = 2

    /// Frames the renderer may hold once decoded bytes stop being the
    /// constraint. Small frames are cheap individually and still cost per-frame
    /// teardown, so a stream whose bytes fit under the ceiling many times over
    /// does not get to queue without end.
    static let maximumFrames = environmentInteger("ENCHRON_RENDERER_LEAD_MAX_FRAMES") ?? 48

    /// Decoded bytes the renderer may hold. This is the decode-surface pressure
    /// bound, and it is what makes the budget scale with resolution: at 200 MB an
    /// 8-bit 4:2:0 8192x4096 frame costs 50.3 MB and lands the stream near four
    /// frames, the same depth VLC and Chromium settle on for large formats,
    /// while 1280x720 stays at the frame ceiling.
    static let maximumDecodedBytes = environmentDouble("ENCHRON_RENDERER_LEAD_MAX_BYTES")
        ?? (200.0 * 1024.0 * 1024.0)

    /// The lead this stream may hold. A stream whose decoded size cannot be
    /// computed keeps the frame ceiling; nothing is known that would justify
    /// tightening it. The reorder floor wins over both ceilings, because a queue
    /// shallower than the encoder's own reordering starves the decoder outright.
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

/// The video samples handed to the renderer that the timeline has not reached
/// yet. Presentation ends arrive in decode order, so the frame the timeline
/// retires next is the earliest of them rather than the one recorded first.
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

    /// When the timeline next retires a frame, which is also the moment the
    /// frame behind it becomes the displayed one. Reading it from the queue
    /// rather than from a nominal frame rate keeps a variable-rate stream exact.
    mutating func nextRetirement(after timelineSeconds: Double) -> Double? {
        presentationEnds.removeAll { $0 <= timelineSeconds }
        return presentationEnds.min()
    }

    mutating func removeAll() {
        presentationEnds.removeAll()
    }
}
