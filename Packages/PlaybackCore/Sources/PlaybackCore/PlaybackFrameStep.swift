@preconcurrency import AVFoundation
import Foundation

public enum PlaybackFrameStepDirection: Sendable, Equatable {
    case forward
    case backward
}
