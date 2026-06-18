import Foundation

nonisolated extension PersistenceDomain {
    public struct UserPreferences: Sendable, Equatable {
        public var resumePolicy: ResumePolicy
        public var playbackEndBehavior: PlaybackEndBehavior
        public var defaultPlaybackSpeed: Double
        public var defaultEnvironmentID: String?
        public var isScreenCurved: Bool
        /// Idle seconds before window playback controls auto-hide; 0 means never (SET-13).
        public var controlsAutoHideSeconds: Int
        /// Whether spatial content auto-enters immersion (SET-14).
        public var entersImmersionForSpatialContent: Bool
        /// Diagnostic log verbosity (SET-23).
        public var logLevel: LogLevel
        /// Whether the performance HUD overlay is shown (SET-25).
        public var showsPerformanceHUD: Bool
        /// When verbose logging reverts automatically (advanced logs).
        public var verboseAutoOff: VerboseAutoOff

        public init(
            resumePolicy: ResumePolicy = .askEveryTime,
            playbackEndBehavior: PlaybackEndBehavior = .stop,
            defaultPlaybackSpeed: Double = 1.0,
            defaultEnvironmentID: String? = nil,
            isScreenCurved: Bool = false,
            controlsAutoHideSeconds: Int = 8,
            entersImmersionForSpatialContent: Bool = false,
            logLevel: LogLevel = .info,
            showsPerformanceHUD: Bool = false,
            verboseAutoOff: VerboseAutoOff = .thirtyMinutes
        ) {
            self.resumePolicy = resumePolicy
            self.playbackEndBehavior = playbackEndBehavior
            self.defaultPlaybackSpeed = defaultPlaybackSpeed
            self.defaultEnvironmentID = defaultEnvironmentID
            self.isScreenCurved = isScreenCurved
            self.controlsAutoHideSeconds = controlsAutoHideSeconds
            self.entersImmersionForSpatialContent = entersImmersionForSpatialContent
            self.logLevel = logLevel
            self.showsPerformanceHUD = showsPerformanceHUD
            self.verboseAutoOff = verboseAutoOff
        }
    }
}
