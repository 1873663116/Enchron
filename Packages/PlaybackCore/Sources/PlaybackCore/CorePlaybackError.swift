import Foundation

enum CorePlaybackError: LocalizedError {
    case audioPrerollTimedOut(Double)
    case firstVideoSampleTimedOut(Double)
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
        case .firstVideoSampleTimedOut(let seconds):
            "No video frame arrived within "
                + "\(seconds.formatted(.number.precision(.fractionLength(0...3)))) "
                + "seconds after the source opened. Confirm that the selected file contains "
                + "media samples and is not only an HLS initialization segment."
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
