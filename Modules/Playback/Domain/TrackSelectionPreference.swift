nonisolated public enum SubtitleTrackSelectionPreference: Codable, Equatable, Sendable {
    case off
    case track(id: String)
}

nonisolated public struct TrackSelectionPreference: Codable, Equatable, Sendable {
    public var audioTrackID: String?
    public var subtitleTrack: SubtitleTrackSelectionPreference?

    public init(
        audioTrackID: String? = nil,
        subtitleTrack: SubtitleTrackSelectionPreference? = nil
    ) {
        self.audioTrackID = audioTrackID
        self.subtitleTrack = subtitleTrack
    }
}
