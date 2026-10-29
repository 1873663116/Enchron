import Foundation
import MediaSource

package nonisolated struct AudioTrackDescriptor: Codable, Equatable, Sendable {
    package var languageCode: String?
    package var displayName: String?
    package var codecName: String?
    package var channelCount: Int?

    package init(
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

package nonisolated enum SubtitleTrackDescriptor: Codable, Equatable, Sendable {
    case off
    case embedded(languageCode: String?, displayName: String?)
    case external(languageCode: String?, displayName: String?)
}

package nonisolated struct PersistedTrackPreference: Codable, Equatable, Sendable {
    package var audio: AudioTrackDescriptor?
    package var subtitle: SubtitleTrackDescriptor?

    package init(
        audio: AudioTrackDescriptor? = nil,
        subtitle: SubtitleTrackDescriptor? = nil
    ) {
        self.audio = audio
        self.subtitle = subtitle
    }
}

package nonisolated enum TrackPreferenceDescriptor {
    package static func audio(_ track: PlaybackModel.AudioTrack) -> AudioTrackDescriptor {
        AudioTrackDescriptor(
            languageCode: track.languageCode,
            displayName: track.displayName,
            codecName: track.codecName,
            channelCount: track.channelCount
        )
    }

    package static func subtitle(
        _ track: PlaybackModel.SubtitleTrack?
    ) -> SubtitleTrackDescriptor {
        guard let track else { return .off }
        if track.isExternal {
            return .external(
                languageCode: track.languageCode,
                displayName: track.displayName
            )
        }
        return .embedded(
            languageCode: track.languageCode,
            displayName: track.displayName
        )
    }
}

package nonisolated enum TrackPreferenceResolver {
    package static func audioTrackID(
        _ descriptor: AudioTrackDescriptor,
        in tracks: [PlaybackModel.AudioTrack]
    ) -> String? {
        guard tracks.isEmpty == false else { return nil }
        let language = normalizedLanguage(descriptor.languageCode)
        let name = normalizedName(descriptor.displayName)
        guard language != nil || name != nil else { return nil }
        let candidates = audioCandidates(in: tracks, language: language, name: name)
        guard candidates.isEmpty == false else { return nil }
        return bestAudio(in: candidates, descriptor: descriptor)?.id
    }

    package static func subtitleSelection(
        _ descriptor: SubtitleTrackDescriptor,
        in tracks: [PlaybackModel.SubtitleTrack]
    ) -> SubtitleTrackSelectionPreference? {
        switch descriptor {
        case .off:
            return .off
        case .embedded(let languageCode, let displayName):
            let language = normalizedLanguage(languageCode)
            let name = normalizedName(displayName)
            guard language != nil || name != nil else { return nil }
            let candidates = subtitleCandidates(
                in: tracks.filter { $0.isExternal == false },
                language: language,
                name: name
            )
            guard let track = bestSubtitle(in: candidates, name: name) else { return nil }
            return .track(id: track.id)
        case .external(let languageCode, let displayName):
            let language = normalizedLanguage(languageCode)
            let name = normalizedName(displayName)
            guard language != nil || name != nil else { return nil }
            let candidates = subtitleCandidates(
                in: tracks.filter(\.isExternal),
                language: language,
                name: name
            )
            guard let track = bestSubtitle(in: candidates, name: name) else { return nil }
            guard let sourceID = externalSourceID(fromTrackID: track.id) else {
                return .track(id: track.id)
            }
            return .externalSource(id: sourceID)
        }
    }

    package static func externalSourceID(fromTrackID trackID: String) -> String? {
        let prefix = "external.subtitle."
        guard trackID.hasPrefix(prefix) else { return nil }
        let remainder = trackID.dropFirst(prefix.count)
        guard let separator = remainder.lastIndex(of: ".") else {
            return remainder.isEmpty ? nil : String(remainder)
        }
        let sourceID = remainder[..<separator]
        return sourceID.isEmpty ? nil : String(sourceID)
    }

    private static func audioCandidates(
        in tracks: [PlaybackModel.AudioTrack],
        language: String?,
        name: String?
    ) -> [PlaybackModel.AudioTrack] {
        if let language {
            let matches = tracks.filter { normalizedLanguage($0.languageCode) == language }
            if matches.isEmpty == false { return matches }
            guard let name else { return [] }
            return tracks.filter { normalizedName($0.displayName) == name }
        }
        guard let name else { return [] }
        return tracks.filter { normalizedName($0.displayName) == name }
    }

    private static func subtitleCandidates(
        in tracks: [PlaybackModel.SubtitleTrack],
        language: String?,
        name: String?
    ) -> [PlaybackModel.SubtitleTrack] {
        if let language {
            let matches = tracks.filter { normalizedLanguage($0.languageCode) == language }
            if matches.isEmpty == false { return matches }
            guard let name else { return [] }
            return tracks.filter { normalizedName($0.displayName) == name }
        }
        guard let name else { return [] }
        return tracks.filter { normalizedName($0.displayName) == name }
    }

    private static func bestAudio(
        in candidates: [PlaybackModel.AudioTrack],
        descriptor: AudioTrackDescriptor
    ) -> PlaybackModel.AudioTrack? {
        let name = normalizedName(descriptor.displayName)
        let codec = normalizedName(descriptor.codecName)
        let channels = descriptor.channelCount
        return candidates.enumerated().map { offset, track in
            var score = 0
            if let name, normalizedName(track.displayName) == name { score += 8 }
            if let channels, track.channelCount == channels { score += 4 }
            if let codec, normalizedName(track.codecName) == codec { score += 2 }
            if track.isDefault { score += 1 }
            return (score, -offset, track)
        }
        .max { ($0.0, $0.1) < ($1.0, $1.1) }?
        .2
    }

    private static func bestSubtitle(
        in candidates: [PlaybackModel.SubtitleTrack],
        name: String?
    ) -> PlaybackModel.SubtitleTrack? {
        candidates.enumerated().map { offset, track in
            var score = 0
            if let name, normalizedName(track.displayName) == name { score += 8 }
            if track.isDefault { score += 1 }
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
