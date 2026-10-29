import Foundation

public struct PlaybackAudioTrackPreference: Sendable, Equatable {
    public let languageCode: String?
    public let displayName: String?
    public let codecName: String?
    public let channelCount: Int?

    public init(
        languageCode: String? = nil,
        displayName: String? = nil,
        codecName: String? = nil,
        channelCount: Int? = nil
    ) {
        self.languageCode = languageCode
        self.displayName = displayName
        self.codecName = codecName
        self.channelCount = channelCount
    }
}

public enum PlaybackInitialAudioSelection: Sendable, Equatable {
    case streamIndex(Int)
    case preference(PlaybackAudioTrackPreference)
}

enum PlaybackAudioTrackMatcher {
    static func streamIndex(
        for selection: PlaybackInitialAudioSelection,
        in tracks: [PlaybackAudioTrack]
    ) -> Int? {
        switch selection {
        case .streamIndex(let index):
            return tracks.contains { $0.streamIndex == index } ? index : nil
        case .preference(let preference):
            return bestTrack(for: preference, in: tracks)?.streamIndex
        }
    }

    private static func bestTrack(
        for preference: PlaybackAudioTrackPreference,
        in tracks: [PlaybackAudioTrack]
    ) -> PlaybackAudioTrack? {
        guard tracks.isEmpty == false else { return nil }
        let language = normalizedLanguage(preference.languageCode)
        let name = normalizedName(preference.displayName)
        guard language != nil || name != nil else { return nil }
        var candidates: [PlaybackAudioTrack]
        if let language {
            let matches = tracks.filter { normalizedLanguage($0.language) == language }
            if matches.isEmpty == false {
                candidates = matches
            } else if let name {
                candidates = tracks.filter { normalizedName($0.label) == name }
            } else {
                return nil
            }
        } else if let name {
            candidates = tracks.filter { normalizedName($0.label) == name }
        } else {
            return nil
        }
        guard candidates.isEmpty == false else { return nil }
        let codec = normalizedName(preference.codecName)
        let channels = preference.channelCount
        return candidates.enumerated().map { offset, track in
            var score = 0
            if let name, normalizedName(track.label) == name { score += 8 }
            if let channels, track.channelCount == channels { score += 4 }
            if let codec, normalizedName(track.codecName) == codec { score += 2 }
            return (score, -offset, track)
        }
        .max { ($0.0, $0.1) < ($1.0, $1.1) }?
        .2
    }

    private static func normalizedLanguage(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false, trimmed != "und", trimmed != "unknown" else {
            return nil
        }
        return trimmed
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
