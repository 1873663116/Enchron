public nonisolated enum ViewingStateAuthority: Sendable, Equatable {
    case enchronPersistence
    case mediaServer
}

public nonisolated struct PlaybackSessionReport: Sendable, Equatable {
    public let positionSeconds: Double
    public let isPaused: Bool
    public let selectedAudioTrackID: String?
    public let selectedSubtitleTrackID: String?

    public init(
        positionSeconds: Double,
        isPaused: Bool,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?
    ) {
        self.positionSeconds = positionSeconds
        self.isPaused = isPaused
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedSubtitleTrackID = selectedSubtitleTrackID
    }
}

public nonisolated protocol PlaybackSessionReporting: Sendable {
    func playbackStarted(_ report: PlaybackSessionReport)
    func playbackProgressed(_ report: PlaybackSessionReport)
    func playbackStopped(_ report: PlaybackSessionReport)
}
