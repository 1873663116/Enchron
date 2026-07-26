import Foundation

enum CorePlaybackError: LocalizedError {
    case seekTimedOut(Double)
    case seekSuperseded(Double)
    case seekTargetUnavailable(Double, Double?)
    case stereoOverrideUnavailable(VideoStereoLayout?)
    case stereoOverrideTimedOut(VideoStereoLayout?)
    case projectionOverrideUnavailable(VideoProjectionOverride?)
    case projectionOverrideTimedOut(VideoProjectionOverride?)

    var errorDescription: String? {
        switch self {
        case .seekTimedOut(let seconds): "Seek to \(seconds) seconds did not reach renderer input coordination."
        case .seekSuperseded(let seconds): "Seek to \(seconds) seconds was superseded by a newer request."
        case .seekTargetUnavailable(let target, let lastPTS):
            "Seek target \(target) seconds is unavailable because the target epoch ended first; last video PTS: \(lastPTS.map { String($0) } ?? "none")."
        case .stereoOverrideUnavailable(let layout):
            "Stereo layout \(layout?.rawValue ?? "source") cannot be applied after the video input ended."
        case .stereoOverrideTimedOut(let layout):
            "Stereo layout \(layout?.rawValue ?? "source") did not reach renderer input coordination."
        case .projectionOverrideUnavailable(let projection):
            "Projection \(projection?.rawValue ?? "source") cannot be applied after the video input ended."
        case .projectionOverrideTimedOut(let projection):
            "Projection \(projection?.rawValue ?? "source") did not reach renderer input coordination."
        }
    }
}
