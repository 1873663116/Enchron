nonisolated public enum SubtitleTrackSelectionPreference: Codable, Equatable, Sendable {
    case off
    case track(id: String)
    case externalSource(id: String)
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

nonisolated struct SubtitleSelectionIntent {
    private(set) var preference: SubtitleTrackSelectionPreference?
    private(set) var revision: UInt64 = 0

    init(preference: SubtitleTrackSelectionPreference? = nil) {
        self.preference = preference
    }

    mutating func restore(_ preference: SubtitleTrackSelectionPreference?) {
        guard revision == 0 else { return }
        self.preference = preference
    }

    mutating func select(_ preference: SubtitleTrackSelectionPreference) {
        revision &+= 1
        self.preference = preference
    }

    func trackID(in tracks: [PlaybackModel.SubtitleTrack]) -> String? {
        tracks.first { track in
            switch preference {
            case .track(let id): track.id == id
            case .externalSource(let id): track.id.hasPrefix("external.subtitle.\(id).")
            case .off, nil: false
            }
        }?.id
    }
}
