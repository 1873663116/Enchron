import Foundation

extension PersistenceDomain {
    public struct UserPreferences: Sendable, Equatable {
        public var resumePolicy: ResumePolicy
        public var playbackEndBehavior: PlaybackEndBehavior
        public var defaultPlaybackSpeed: Double
        public var defaultEnvironmentID: String?
        public var isScreenCurved: Bool

        public init(
            resumePolicy: ResumePolicy = .askEveryTime,
            playbackEndBehavior: PlaybackEndBehavior = .stop,
            defaultPlaybackSpeed: Double = 1.0,
            defaultEnvironmentID: String? = nil,
            isScreenCurved: Bool = false
        ) {
            self.resumePolicy = resumePolicy
            self.playbackEndBehavior = playbackEndBehavior
            self.defaultPlaybackSpeed = defaultPlaybackSpeed
            self.defaultEnvironmentID = defaultEnvironmentID
            self.isScreenCurved = isScreenCurved
        }
    }
}
