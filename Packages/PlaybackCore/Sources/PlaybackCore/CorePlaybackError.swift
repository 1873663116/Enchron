import Foundation

enum CorePlaybackError: LocalizedError {
    case audioPrerollTimedOut(Double)
    case firstVideoFrameTimedOut(Double, rendererError: String?)
    case seekTimedOut(Double)
    case seekSuperseded(Double)
    case seekTargetUnavailable(Double, Double?)
    case stereoOverrideUnavailable(VideoStereoLayout?)
    case stereoOverrideTimedOut(VideoStereoLayout?)
    case projectionOverrideUnavailable(VideoProjectionOverride?)
    case projectionOverrideTimedOut(VideoProjectionOverride?)
    case formatOverridesUnavailable(VideoStereoLayout?, VideoProjectionOverride?)
    case formatOverridesTimedOut(VideoStereoLayout?, VideoProjectionOverride?)

    var errorDescription: String? {
        switch self {
        case .audioPrerollTimedOut(let seconds):
            "Audio did not preroll through the timeline start at \(seconds) seconds."
        case .firstVideoFrameTimedOut(let seconds, let rendererError):
            if let rendererError, rendererError.isEmpty == false {
                rendererError
            } else {
                "No video frame was displayed within "
                    + "\(seconds.formatted(.number.precision(.fractionLength(0...3)))) "
                    + "seconds after playback started."
            }
        case .seekTimedOut(let seconds): "Seek to \(seconds) seconds did not reach renderer input coordination."
        case .seekSuperseded(let seconds): "Seek to \(seconds) seconds was superseded by a newer request."
        case .seekTargetUnavailable(let target, let lastPTS):
            "Seek target \(target) seconds is unavailable because the target epoch ended first; last video PTS: \(lastPTS.map { String($0) } ?? "none")."
        case .stereoOverrideUnavailable(let layout):
            "Stereo layout \(layout?.rawValue ?? "source") cannot be applied after the video input ended."
        case .stereoOverrideTimedOut(let layout):
            "Stereo layout \(layout?.rawValue ?? "source") did not reach renderer input coordination."
        case .projectionOverrideUnavailable(let projection):
            "Projection \(projection?.diagnosticLabel ?? "source") cannot be applied after the video input ended."
        case .projectionOverrideTimedOut(let projection):
            "Projection \(projection?.diagnosticLabel ?? "source") did not reach renderer input coordination."
        case .formatOverridesUnavailable(let stereo, let projection):
            "Media format \(stereo?.rawValue ?? "source") / \(projection?.diagnosticLabel ?? "source") cannot be applied after the video input ended."
        case .formatOverridesTimedOut(let stereo, let projection):
            "Media format \(stereo?.rawValue ?? "source") / \(projection?.diagnosticLabel ?? "source") did not reach renderer input coordination."
        }
    }
}
