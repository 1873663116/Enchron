@preconcurrency import AVFoundation
import Foundation

public enum PlaybackFrameStepDirection: Sendable, Equatable {
    case forward
    case backward
}

enum PlaybackFrameStepOutcome: Equatable {
    case advanced(to: CMTime)
    case needsSeek
}
