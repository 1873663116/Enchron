import Foundation

nonisolated extension PlaybackCoreDomain {
    public struct MediaFile: Sendable, Equatable {
        public let url: URL
        public let containerFormat: String
        public let audioTracks: [AudioTrack]
        public let subtitleTracks: [SubtitleTrack]

        public init(
            url: URL,
            containerFormat: String,
            audioTracks: [AudioTrack] = [],
            subtitleTracks: [SubtitleTrack] = []
        ) {
            self.url = url
            self.containerFormat = containerFormat
            self.audioTracks = audioTracks
            self.subtitleTracks = subtitleTracks
        }
    }
}
