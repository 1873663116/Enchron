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
    public struct Entry: Hashable, Sendable, Identifiable {
        public let label: String
        public let value: String

        public var id: String { label + value }
    }

    public let information: [Entry]
    public let languages: [Entry]
    public let accessibility: [Entry]
    public let video: [Entry]
    public let audio: [Entry]
    public let subtitles: [Entry]
    public let file: [Entry]

    public init(metadata: EmbyItemMetadata, sources: [EmbyMediaSourceDescription]) {
        var information: [Entry] = []
        if let year = metadata.productionYear {
            information.append(Entry(label: String(localized: "Released"), value: String(year)))
        }
        if let rating = metadata.officialRating, rating.isEmpty == false {
            information.append(Entry(label: String(localized: "Rated"), value: rating))
        }
        if metadata.studios.isEmpty == false {
            information.append(
                Entry(label: String(localized: "Studios"), value: metadata.studios.map(\.name).joined(separator: ", "))
            )
        }
        if metadata.productionLocations.isEmpty == false {
            information.append(
                Entry(label: String(localized: "Region"), value: metadata.productionLocations.joined(separator: ", "))
            )
        }
        self.information = information

        let streams = sources.flatMap(\.mediaStreams)
        let audioStreams = streams.filter { $0.kind == .audio }
        let subtitleStreams = streams.filter { $0.kind == .subtitle }

        var languages: [Entry] = []
        if let original = audioStreams.first(where: \.isDefault) ?? audioStreams.first,
           let name = Self.languageName(original) {
            languages.append(Entry(label: String(localized: "Original Audio"), value: name))
        }
        if audioStreams.isEmpty == false {
            languages.append(
                Entry(label: String(localized: "Audio"), value: Self.joined(audioStreams.compactMap(Self.languageName)))
            )
        }
        if subtitleStreams.isEmpty == false {
            languages.append(
                Entry(label: String(localized: "Subtitles"), value: Self.joined(subtitleStreams.compactMap(Self.languageName)))
            )
        }
        self.languages = languages

        var accessibility: [Entry] = []
        if subtitleStreams.contains(where: \.isHearingImpaired) {
            accessibility.append(Entry(
                label: String(localized: "SDH"),
                value: "Subtitles for the deaf and hard of hearing describe sounds beyond dialogue."
            ))
        }
        if audioStreams.contains(where: Self.isAudioDescription) {
            accessibility.append(Entry(
                label: String(localized: "AD"),
                value: "Audio description narrates what happens on screen between lines of dialogue."
            ))
        }
        self.accessibility = accessibility

        self.video = Self.videoEntries(streams.filter { $0.kind == .video })
        self.audio = Self.uniqued(audioStreams.map { stream in
            let name = Self.trackName(stream)
            return Entry(label: name, value: Self.audioDescription(stream, omittingLanguage: name))
        })
        self.subtitles = Self.uniqued(subtitleStreams.map { stream in
            let name = Self.trackName(stream)
            return Entry(label: name, value: Self.subtitleDescription(stream, omittingLanguage: name))
        })
        self.file = Self.fileEntries(sources)
    }

    private static func videoEntries(_ streams: [EmbyMediaStream]) -> [Entry] {
        var entries: [Entry] = []
        func add(_ label: String, _ values: [String?]) {
            let distinct = joined(values.compactMap { $0 })
            if distinct.isEmpty == false { entries.append(Entry(label: label, value: distinct)) }
        }
        add("Resolution", streams.map { stream in
            guard let width = stream.width, let height = stream.height else { return nil }
            return "\(width) × \(height)"
        })
        add("Codec", streams.map { $0.codec?.nonEmptyValue?.uppercased() })
        add("Profile", streams.map { $0.profile?.nonEmptyValue })
        add("Dynamic Range", streams.map { $0.videoRange?.nonEmptyValue?.uppercased() })
        add("Dolby Vision", streams.map { stream in
            guard stream.extendedVideoType?.caseInsensitiveCompare("DolbyVision") == .orderedSame
            else { return nil }
            return stream.extendedVideoSubTypeDescription?.nonEmptyValue
        })
        add("Bit Depth", streams.map { $0.bitDepth.map { "\($0)-bit" } })
        add("Frame Rate", streams.map { $0.averageFrameRate.map(frameRate) })
        add("Aspect Ratio", streams.map { $0.aspectRatio?.nonEmptyValue })
        add("Pixel Format", streams.map { $0.pixelFormat?.nonEmptyValue })
        add("Video Bitrate", streams.map { $0.bitRate.map(bitrate) })
        return entries
    }

    private static func fileEntries(_ sources: [EmbyMediaSourceDescription]) -> [Entry] {
        guard sources.isEmpty == false else { return [] }
        var entries: [Entry] = []
        let containers = joined(sources.compactMap { $0.container?.nonEmptyValue.map { $0.uppercased() } })
        if containers.isEmpty == false {
            entries.append(Entry(label: String(localized: "Container"), value: containers))
        }
        guard sources.count == 1, let source = sources.first else {
            entries.append(Entry(label: String(localized: "Files"), value: "\(sources.count)"))
            return entries
        }
        if let size = source.sizeInBytes {
            entries.append(Entry(label: String(localized: "Size"), value: size.formatted(.byteCount(style: .file))))
        }
        if let rate = source.bitrate {
            entries.append(Entry(label: String(localized: "Total Bitrate"), value: bitrate(rate)))
        }
        entries.append(Entry(label: String(localized: "Version"), value: source.displayName))
        return entries
    }

    private static func trackName(_ stream: EmbyMediaStream) -> String {
        stream.title?.nonEmptyValue ?? languageName(stream) ?? "Track \(stream.index)"
    }

    private static func bitrate(_ bitsPerSecond: Int) -> String {
        if bitsPerSecond >= 10_000_000 {
            return "\((Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(0)))) Mbps"
        }
        if bitsPerSecond >= 1_000_000 {
            return "\((Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(1)))) Mbps"
        }
        return "\(bitsPerSecond / 1000) kbps"
    }

    private static func frameRate(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(0...3)))) fps"
    }

    private static func languageName(_ stream: EmbyMediaStream) -> String? {
        stream.displayLanguage?.nonEmptyValue ?? stream.language?.nonEmptyValue
    }

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

    private static func joined(_ values: [String]) -> String {
        uniqued(values).joined(separator: ", ")
    }

    private static func uniqued<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen: Set<Value> = []
        return values.filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nonEmptyValue: String? { isEmpty ? nil : self }
}
