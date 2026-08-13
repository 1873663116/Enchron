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
    /// Which languages the release carries. What each track is made of belongs to ``audio`` and
    /// ``subtitles``, so neither column repeats the other.
    public let languages: [Entry]
    public let accessibility: [Entry]
    /// How the picture is encoded, read off the stream the server measured.
    public let video: [Entry]
    /// One row per audio track, labelled by the track's own name where a release gives one, because
    /// that is what tells two tracks of the same language apart.
    public let audio: [Entry]
    /// One row per subtitle track.
    public let subtitles: [Entry]
    /// The file the streams live in.
    public let file: [Entry]

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
                Entry(label: "Audio", value: Self.joined(audioStreams.compactMap(Self.languageName)))
            )
        }
        if subtitleStreams.isEmpty == false {
            languages.append(
                Entry(label: "Subtitles", value: Self.joined(subtitleStreams.compactMap(Self.languageName)))
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

        self.video = Self.videoEntries(streams.first { $0.kind == .video })
        self.audio = audioStreams.map { stream in
            let name = Self.trackName(stream)
            return Entry(label: name, value: Self.audioDescription(stream, omittingLanguage: name))
        }
        self.subtitles = subtitleStreams.map { stream in
            let name = Self.trackName(stream)
            return Entry(label: name, value: Self.subtitleDescription(stream, omittingLanguage: name))
        }
        self.file = Self.fileEntries(source)
    }

    private static func videoEntries(_ stream: EmbyMediaStream?) -> [Entry] {
        guard let stream else { return [] }
        var entries: [Entry] = []
        if let width = stream.width, let height = stream.height {
            entries.append(Entry(label: "Resolution", value: "\(width) × \(height)"))
        }
        if let codec = stream.codec?.nonEmptyValue {
            entries.append(Entry(label: "Codec", value: codec.uppercased()))
        }
        if let profile = stream.profile?.nonEmptyValue {
            entries.append(Entry(label: "Profile", value: profile))
        }
        if let range = stream.videoRange?.nonEmptyValue {
            entries.append(Entry(label: "Dynamic Range", value: range.uppercased()))
        }
        if let depth = stream.bitDepth {
            entries.append(Entry(label: "Bit Depth", value: "\(depth)-bit"))
        }
        if let rate = stream.averageFrameRate {
            entries.append(Entry(label: "Frame Rate", value: frameRate(rate)))
        }
        if let ratio = stream.aspectRatio?.nonEmptyValue {
            entries.append(Entry(label: "Aspect Ratio", value: ratio))
        }
        if let format = stream.pixelFormat?.nonEmptyValue {
            entries.append(Entry(label: "Pixel Format", value: format))
        }
        if let bitRate = stream.bitRate {
            entries.append(Entry(label: "Video Bitrate", value: bitrate(bitRate)))
        }
        return entries
    }

    private static func fileEntries(_ source: EmbyMediaSourceDescription?) -> [Entry] {
        guard let source else { return [] }
        var entries: [Entry] = []
        if let container = source.container?.nonEmptyValue {
            entries.append(Entry(label: "Container", value: container.uppercased()))
        }
        if let size = source.sizeInBytes {
            entries.append(Entry(label: "Size", value: size.formatted(.byteCount(style: .file))))
        }
        if let rate = source.bitrate {
            entries.append(Entry(label: "Total Bitrate", value: bitrate(rate)))
        }
        entries.append(Entry(label: "Version", value: source.displayName))
        return entries
    }

    /// A release names its tracks when the language alone would not tell them apart, which is the
    /// case whenever it carries two dubs of one language.
    private static func trackName(_ stream: EmbyMediaStream) -> String {
        stream.title?.nonEmptyValue ?? languageName(stream) ?? "Track \(stream.index)"
    }

    /// Bits per second as the unit that keeps the number readable: kilobits under ten megabits,
    /// megabits above.
    private static func bitrate(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 10_000_000 {
            return "\((Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(0)))) Mbps"
        }
        if bitsPerSecond >= 1_000_000 {
            return "\((Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(1)))) Mbps"
        }
        return "\(bitsPerSecond / 1000) kbps"
    }

    /// Film rates are repeating decimals, so they are shown to three places and trailing zeros are
    /// dropped: 23.976 stays exact and 25 does not become 25.000.
    private static func frameRate(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...3)))) fps"
    }

    private static func languageName(_ stream: EmbyMediaStream) -> String? {
        stream.displayLanguage?.nonEmptyValue ?? stream.language?.nonEmptyValue
    }

    /// What one audio track is made of, in the order a listener would ask: which codec, how many
    /// channels, how much data, at what sample rate.
    private static func audioDescription(
        _ stream: EmbyMediaStream,
        omittingLanguage label: String
    ) -> String {
        var parts: [String] = []
        if let codec = stream.codec?.nonEmptyValue { parts.append(codec.uppercased()) }
        if let layout = stream.channelLayout?.nonEmptyValue {
            parts.append(layout)
        } else if let channels = stream.channels {
            parts.append("\(channels) ch")
        }
        if let depth = stream.bitDepth { parts.append("\(depth)-bit") }
        if let rate = stream.bitRate { parts.append(bitrate(rate)) }
        if let sampleRate = stream.sampleRate {
            parts.append("\(sampleRate / 1000) kHz")
        }
        if let language = languageName(stream), language != label { parts.append(language) }
        if stream.isDefault { parts.append("Default") }
        return parts.isEmpty ? "Undetermined" : parts.joined(separator: " · ")
    }

    private static func subtitleDescription(
        _ stream: EmbyMediaStream,
        omittingLanguage label: String
    ) -> String {
        var parts: [String] = []
        if let codec = stream.codec?.nonEmptyValue { parts.append(codec.uppercased()) }
        if let language = languageName(stream), language != label { parts.append(language) }
        if stream.isExternal { parts.append("External") }
        if stream.isForced { parts.append("Forced") }
        if stream.isHearingImpaired { parts.append("SDH") }
        if stream.isDefault { parts.append("Default") }
        return parts.isEmpty ? "Undetermined" : parts.joined(separator: " · ")
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
