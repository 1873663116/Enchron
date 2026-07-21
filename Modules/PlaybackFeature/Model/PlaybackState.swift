import Foundation


nonisolated extension PlaybackModel {
    public struct PlaybackPosition: Sendable, Equatable {
        public let seconds: Double
        public let duration: Double

        public init(seconds: Double, duration: Double) {
            self.seconds = max(0, seconds)
            self.duration = max(0, duration)
        }

        public var progress: Double {
            guard duration > 0 else { return 0 }
            return min(max(seconds / duration, 0), 1)
        }
    }
}


nonisolated extension PlaybackModel {
    public struct PlaybackSpeed: Sendable, Equatable, Hashable {
        public let value: Double

        public init(_ value: Double) {
            self.value = min(max(value, 0.25), 5.0)
        }

        public static let `default` = PlaybackSpeed(1.0)
        public static let speed0_25 = PlaybackSpeed(0.25)
        public static let speed0_5 = PlaybackSpeed(0.5)
        public static let speed0_75 = PlaybackSpeed(0.75)
        public static let speed1_0 = PlaybackSpeed(1.0)
        public static let speed1_25 = PlaybackSpeed(1.25)
        public static let speed1_5 = PlaybackSpeed(1.5)
        public static let speed1_75 = PlaybackSpeed(1.75)
        public static let speed2_0 = PlaybackSpeed(2.0)
        public static let speed3_0 = PlaybackSpeed(3.0)
        public static let speed5_0 = PlaybackSpeed(5.0)

        public static let allCases: [PlaybackSpeed] = [
            .speed0_25, .speed0_5, .speed0_75, .speed1_0, .speed1_25, .speed1_5, .speed1_75, .speed2_0, .speed3_0, .speed5_0
        ]
    }
}


public enum PlaybackError: Error, Sendable {
    case failedToLoad(URL)
    case unsupportedMedia
    case runtime(String)
}

public enum PlaybackEvent: Sendable {
    case started
    case paused
    case resumed
    case ended
    case positionUpdated(PlaybackModel.PlaybackPosition)
    case speedChanged(PlaybackModel.PlaybackSpeed)
    case trackSwitched
    case mediaProfileDetected(PlaybackModel.MediaProfile)
    case failed(PlaybackError)
}


public nonisolated protocol PlaybackEventListening: AnyObject {
    func playbackDidStart()
    func playbackDidPause()
    func playbackDidResume()
    func playbackDidEnd()
    func playbackDidUpdatePosition(_ position: PlaybackModel.PlaybackPosition)
    func playbackDidChangeSpeed(_ speed: PlaybackModel.PlaybackSpeed)
    func playbackDidSwitchTrack()
    func playbackDidEncounterError(_ error: PlaybackError)
}

