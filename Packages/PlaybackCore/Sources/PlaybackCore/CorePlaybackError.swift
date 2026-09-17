import Foundation

struct AudioRendererRetirementError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

enum CorePlaybackError: LocalizedError {
    case noPlayableMediaStream
    case mediaInputTruncated(deliveredEndSeconds: Double?, declaredDurationSeconds: Double)
    case audioPrerollTimedOut(Double)
    case firstVideoFrameTimedOut(Double, rendererError: String?)
    case seekTimedOut(Double)
    case seekSuperseded(Double)
    case stereoOverrideUnavailable(VideoStereoLayout?)
    case stereoOverrideTimedOut(VideoStereoLayout?)
    case projectionOverrideUnavailable(VideoProjectionOverride?)
    case projectionOverrideTimedOut(VideoProjectionOverride?)
    case formatOverridesUnavailable(VideoStereoLayout?, VideoProjectionOverride?)
    case formatOverridesTimedOut(VideoStereoLayout?, VideoProjectionOverride?)

    var errorDescription: String? {
        switch self {
        case .noPlayableMediaStream:
            "The selected source has no playable audio or video stream."
        case .mediaInputTruncated(let deliveredEndSeconds, let declaredDurationSeconds):
            "Media input ended at "
                + "\(deliveredEndSeconds.map { $0.formatted(.number.precision(.fractionLength(0...3))) } ?? "unknown") "
                + "seconds, before the declared duration of "
                + "\(declaredDurationSeconds.formatted(.number.precision(.fractionLength(0...3)))) seconds."
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
