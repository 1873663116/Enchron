@preconcurrency import AVFoundation
import Foundation

/// Which way a one-frame step moves, and therefore what it costs.
///
/// The two directions are not symmetric. The frame after the displayed one is
/// still queued in the renderer, so stepping forward is a timeline move. The
/// frame before it has been displayed and retired, and only decoding from the
/// preceding keyframe brings it back, so stepping backward is a seek. mpv and
/// VLC both draw the line in the same place.
public enum PlaybackFrameStepDirection: Sendable, Equatable {
    case forward
    case backward
}

/// What a step forward found when it looked at the renderer's queue.
enum PlaybackFrameStepOutcome: Equatable {
    /// The renderer already held the next frame and the timeline moved onto it.
    case advanced(to: CMTime)
    /// Nothing is queued past the timeline, so only a seek can produce the frame.
    case needsSeek
}
