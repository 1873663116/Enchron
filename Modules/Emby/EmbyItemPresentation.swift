import Foundation

public struct EmbyTechnicalBadges: Equatable, Sendable {
    public let resolution: String?
    public let videoRange: String?
    public let audioFormat: String?
    public let hasSubtitles: Bool

    public var labels: [String] {
        var values: [String] = []
        if let resolution { values.append(resolution) }
        if let videoRange { values.append(videoRange) }
        if let audioFormat { values.append(audioFormat) }
        if hasSubtitles { values.append("CC") }
        return values
    }

    public init(source: EmbyMediaSourceDescription?) {
        let streams = source?.mediaStreams ?? []
        let video = streams.first { $0.kind == .video && $0.isDefault } ?? streams.first { $0.kind == .video }
        let audio = streams.first { $0.kind == .audio && $0.isDefault } ?? streams.first { $0.kind == .audio }

        resolution = video?.width.flatMap(Self.resolutionLabel)
        videoRange = video?.videoRange.flatMap(Self.videoRangeLabel)
        audioFormat = audio.map(Self.audioLabel)
        hasSubtitles = streams.contains { $0.kind == .subtitle }
    }

    private static func resolutionLabel(_ width: Int) -> String? {
        switch width {
        case 7000...: "8K"
        case 3400..<7000: "4K"
        case 2000..<3400: "2K"
        case 1200..<2000: "HD"
        case 1..<1200: "SD"
        default: nil
        }
    }

    private static func videoRangeLabel(_ range: String) -> String? {
        switch range.lowercased() {
        case "dolbyvision": "Dolby Vision"
        case "hdr", "hdr10": "HDR"
        case "hdr10plus": "HDR10+"
        case "hlg": "HLG"
        case "sdr": nil
        default: range
        }
    }

    private static func audioLabel(_ stream: EmbyMediaStream) -> String {
        let codec = switch (stream.codec ?? "").lowercased() {
        case "truehd": "Dolby TrueHD"
        case "eac3": "Dolby Digital Plus"
        case "ac3": "Dolby Digital"
        case "dts": "DTS"
        case "flac": "FLAC"
        case "aac": "AAC"
        case let other: other.uppercased()
        }
        guard let layout = stream.channelLayout, layout.isEmpty == false else { return codec }
        return "\(codec) \(layout)"
    }
}

public struct EmbyAboutSections: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String

        public var id: String { label + value }
    }

    /// Genres are not here: the About block prints them under the title, the way the Apple TV app
    /// does, so repeating them as an Information row would say the same thing twice.
    public let information: [Entry]
    public let languages: [Entry]
    public let accessibility: [Entry]

    public init(metadata: EmbyItemMetadata, source: EmbyMediaSourceDescription?) {
        var information: [Entry] = []
        if let year = metadata.productionYear {
            information.append(Entry(label: "Released", value: String(year)))
        }
        if let rating = metadata.officialRating, rating.isEmpty == false {
            information.append(Entry(label: "Rated", value: rating))
        }
        if metadata.studios.isEmpty == false {
            information.append(
                Entry(label: "Studios", value: metadata.studios.map(\.name).joined(separator: ", "))
            )
        }
        if metadata.productionLocations.isEmpty == false {
            information.append(
                Entry(label: "Region", value: metadata.productionLocations.joined(separator: ", "))
            )
        }
        self.information = information

        let streams = source?.mediaStreams ?? []
        let audioStreams = streams.filter { $0.kind == .audio }
        let subtitleStreams = streams.filter { $0.kind == .subtitle }

        var languages: [Entry] = []
        if let original = audioStreams.first(where: \.isDefault) ?? audioStreams.first,
           let name = Self.languageName(original) {
            languages.append(Entry(label: "Original Audio", value: name))
        }
        if audioStreams.isEmpty == false {
            languages.append(
                Entry(label: "Audio", value: Self.joined(audioStreams.map(Self.audioDescription)))
            )
        }
        if subtitleStreams.isEmpty == false {
            languages.append(
                Entry(label: "Subtitles", value: Self.joined(subtitleStreams.map(Self.subtitleDescription)))
            )
        }
        self.languages = languages

        var accessibility: [Entry] = []
        if subtitleStreams.contains(where: \.isHearingImpaired) {
            accessibility.append(Entry(
                label: "SDH",
                value: "Subtitles for the deaf and hard of hearing describe sounds beyond dialogue."
            ))
        }
        if audioStreams.contains(where: Self.isAudioDescription) {
            accessibility.append(Entry(
                label: "AD",
                value: "Audio description narrates what happens on screen between lines of dialogue."
            ))
        }
        self.accessibility = accessibility
    }

    private static func languageName(_ stream: EmbyMediaStream) -> String? {
        stream.displayLanguage?.nonEmptyValue ?? stream.language?.nonEmptyValue
    }

    private static func audioDescription(_ stream: EmbyMediaStream) -> String {
        var value = languageName(stream) ?? "Undetermined"
        if let codec = stream.codec?.nonEmptyValue { value += " (\(codec.uppercased())" }
        if let layout = stream.channelLayout?.nonEmptyValue, stream.codec?.nonEmptyValue != nil {
            value += " \(layout)"
        }
        if stream.codec?.nonEmptyValue != nil { value += ")" }
        return value
    }

    private static func subtitleDescription(_ stream: EmbyMediaStream) -> String {
        var value = languageName(stream) ?? "Undetermined"
        if stream.isHearingImpaired { value += " (SDH)" }
        return value
    }

    private static func isAudioDescription(_ stream: EmbyMediaStream) -> Bool {
        let haystack = [stream.displayTitle, stream.language].compactMap { $0?.lowercased() }
        return haystack.contains { $0.contains("description") || $0.contains(" ad") }
    }

    /// Emby lists one stream per track, so the same language recurs; the About block reads as a
    /// language list, not a track list.
    private static func joined(_ values: [String]) -> String {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
}

private extension String {
    var nonEmptyValue: String? { isEmpty ? nil : self }
}
