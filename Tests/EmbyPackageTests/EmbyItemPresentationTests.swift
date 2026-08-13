import Testing
@testable import Emby

@Suite("Emby detail presentation")
struct EmbyItemPresentationTests {
    @Test("badges name the resolution class, video range, audio format, and subtitle availability")
    func badgesFromStreams() {
        let badges = EmbyTechnicalBadges(source: source(streams: [
            stream(.video, codec: "hevc", width: 3840, height: 1604, videoRange: "DolbyVision"),
            stream(.audio, codec: "eac3", language: "jpn", channelLayout: "5.1", isDefault: true),
            stream(.subtitle, codec: "subrip", language: "eng"),
        ]))

        #expect(badges.labels == ["4K", "Dolby Vision", "Dolby Digital Plus 5.1", "CC"])
    }

    @Test("standard dynamic range and missing subtitles drop their badges")
    func badgesOmitNeutralValues() {
        let badges = EmbyTechnicalBadges(source: source(streams: [
            stream(.video, codec: "h264", width: 1920, height: 1080, videoRange: "SDR"),
            stream(.audio, codec: "aac", language: "eng", channelLayout: "stereo", isDefault: true),
        ]))

        #expect(badges.labels == ["HD", "AAC stereo"])
        #expect(badges.hasSubtitles == false)
    }

    @Test("a source without streams yields no badges")
    func badgesWithoutSource() {
        #expect(EmbyTechnicalBadges(source: nil).labels.isEmpty)
    }

    @Test("about groups information, languages, and accessibility")
    func aboutSections() {
        let streams = [
            stream(.audio, codec: "eac3", language: "jpn", displayLanguage: "Japanese", channelLayout: "5.1", isDefault: true),
            stream(.audio, codec: "eac3", language: "eng", displayLanguage: "English", channelLayout: "5.1"),
            stream(.subtitle, codec: "subrip", language: "eng", displayLanguage: "English"),
            stream(.subtitle, codec: "subrip", language: "eng", displayLanguage: "English", isHearingImpaired: true),
        ]
        let sections = EmbyAboutSections(metadata: metadata(), source: source(streams: streams))

        #expect(sections.information.map(\.label) == ["Released", "Rated", "Genres", "Studios", "Region"])
        #expect(sections.information.first?.value == "2025")
        #expect(sections.languages.map(\.label) == ["Original Audio", "Audio", "Subtitles"])
        #expect(sections.languages[0].value == "Japanese")
        #expect(sections.languages[1].value == "Japanese (EAC3 5.1), English (EAC3 5.1)")
        #expect(sections.languages[2].value == "English, English (SDH)")
        #expect(sections.accessibility.map(\.label) == ["SDH"])
    }

    @Test("accessibility stays empty when no track claims it")
    func aboutWithoutAccessibility() {
        let sections = EmbyAboutSections(
            metadata: metadata(),
            source: source(streams: [stream(.subtitle, codec: "subrip", language: "eng")])
        )

        #expect(sections.accessibility.isEmpty)
    }

    private func metadata() -> EmbyItemMetadata {
        EmbyItemMetadata(
            id: EmbyItemID(rawValue: "1"),
            name: "Sample",
            imageTags: EmbyImageTags(),
            overview: "Overview",
            runTimeTicks: 59_400_000_000,
            userData: nil,
            entityTag: "etag",
            sizeInBytes: 1,
            productionYear: 2025,
            officialRating: "R",
            communityRating: 8.5,
            genres: ["Animation", "Action"],
            studios: [EmbyStudio(name: "MAPPA")],
            people: [],
            productionLocations: ["Japan"]
        )
    }

    private func source(streams: [EmbyMediaStream]) -> EmbyMediaSourceDescription {
        EmbyMediaSourceDescription(
            id: EmbyMediaSourceID(rawValue: "source"),
            displayName: "Sample",
            container: "mkv",
            mediaStreams: streams
        )
    }

    private func stream(
        _ kind: EmbyMediaStreamKind,
        codec: String,
        language: String? = nil,
        displayLanguage: String? = nil,
        channelLayout: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        videoRange: String? = nil,
        isDefault: Bool = false,
        isHearingImpaired: Bool = false
    ) -> EmbyMediaStream {
        EmbyMediaStream(
            index: 0,
            kind: kind,
            codec: codec,
            language: language,
            displayLanguage: displayLanguage,
            displayTitle: nil,
            channels: nil,
            channelLayout: channelLayout,
            width: width,
            height: height,
            videoRange: videoRange,
            isDefault: isDefault,
            isForced: false,
            isExternal: false,
            isHearingImpaired: isHearingImpaired,
            deliveryURL: nil
        )
    }
}
