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
        let sections = EmbyAboutSections(metadata: metadata(), sources: [source(streams: streams)])

        #expect(sections.information.map(\.label) == ["Released", "Rated", "Studios", "Region"])
        #expect(sections.information.first?.value == "2025")
        #expect(sections.languages.map(\.label) == ["Original Audio", "Audio", "Subtitles"])
        #expect(sections.languages[0].value == "Japanese")
        // The Languages column names languages; what a track is made of is the Audio column's job.
        #expect(sections.languages[1].value == "Japanese, English")
        #expect(sections.languages[2].value == "English")
        #expect(sections.accessibility.map(\.label) == ["SDH"])
    }

    @Test("every audio and subtitle track gets its own row, without repeating its own language")
    func aboutTracks() {
        let streams = [
            stream(.audio, codec: "dts", language: "jpn", displayLanguage: "Japanese", channelLayout: "5.1", bitRate: 1_536_000, sampleRate: 48000, isDefault: true),
            stream(.audio, codec: "ac3", language: "chi", displayLanguage: "Chinese", channelLayout: "stereo", bitRate: 192_000, sampleRate: 48000, title: "Mandarin"),
            stream(.subtitle, codec: "PGSSUB", language: "eng", displayLanguage: "English"),
        ]
        let sections = EmbyAboutSections(metadata: metadata(), sources: [source(streams: streams)])

        #expect(sections.audio.map(\.label) == ["Japanese", "Mandarin"])
        #expect(sections.audio[0].value == "DTS · 5.1 · 1.5 Mbps · 48 kHz · Default")
        #expect(sections.audio[1].value == "AC3 · stereo · 192 kbps · 48 kHz · Chinese")
        #expect(sections.subtitles.map(\.label) == ["English"])
        #expect(sections.subtitles[0].value == "PGSSUB")
    }

    @Test("the video column reads the picture off the video stream")
    func aboutVideo() {
        let sections = EmbyAboutSections(
            metadata: metadata(),
            sources: [source(streams: [stream(
                .video,
                codec: "hevc",
                width: 1920,
                height: 1080,
                videoRange: "SDR",
                bitRate: 7_638_461,
                bitDepth: 10,
                profile: "Main 10",
                averageFrameRate: 23.976025,
                aspectRatio: "16:9"
            )])]
        )

        #expect(sections.video.map(\.label) == [
            "Resolution", "Codec", "Profile", "Dynamic Range", "Bit Depth",
            "Frame Rate", "Aspect Ratio", "Video Bitrate",
        ])
        #expect(sections.video[0].value == "1920 × 1080")
        #expect(sections.video[5].value == "23.976 fps")
        #expect(sections.video[7].value == "7.6 Mbps")
    }

    @Test("Dolby Vision names its own profile, which the codec profile never distinguishes")
    func aboutDolbyVisionProfile() {
        let sections = EmbyAboutSections(
            metadata: metadata(),
            sources: [source(streams: [stream(
                .video,
                codec: "hevc",
                videoRange: "DolbyVision",
                extendedVideoType: "DolbyVision",
                extendedVideoSubTypeDescription: "Profile 7.6 (Bluray)",
                profile: "Main 10"
            )])]
        )

        #expect(sections.video.map(\.label) == ["Codec", "Profile", "Dynamic Range", "Dolby Vision"])
        #expect(sections.video[1].value == "Main 10")
        #expect(sections.video[3].value == "Profile 7.6 (Bluray)")
    }

    @Test("an HDR10 stream names no Dolby Vision profile")
    func aboutWithoutDolbyVision() {
        let sections = EmbyAboutSections(
            metadata: metadata(),
            sources: [source(streams: [stream(
                .video,
                codec: "hevc",
                videoRange: "HDR 10",
                extendedVideoType: "Hdr10",
                extendedVideoSubTypeDescription: "HDR 10"
            )])]
        )

        #expect(sections.video.map(\.label).contains("Dolby Vision") == false)
    }

    @Test("the file column carries the container, its size, and its total bitrate")
    func aboutFile() {
        let sections = EmbyAboutSections(
            metadata: metadata(),
            sources: [EmbyMediaSourceDescription(
                id: EmbyMediaSourceID(rawValue: "source"),
                displayName: "Sample",
                container: "mkv",
                sizeInBytes: 3_595_581_174,
                bitrate: 7_638_461,
                mediaStreams: []
            )]
        )

        #expect(sections.file.map(\.label) == ["Container", "Size", "Total Bitrate", "Version"])
        #expect(sections.file[0].value == "MKV")
        #expect(sections.file[2].value == "7.6 Mbps")
    }

    @Test("accessibility stays empty when no track claims it")
    func aboutWithoutAccessibility() {
        let sections = EmbyAboutSections(
            metadata: metadata(),
            sources: [source(streams: [stream(.subtitle, codec: "subrip", language: "eng")])]
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
        extendedVideoType: String? = nil,
        extendedVideoSubTypeDescription: String? = nil,
        bitRate: Int? = nil,
        bitDepth: Int? = nil,
        sampleRate: Int? = nil,
        profile: String? = nil,
        averageFrameRate: Double? = nil,
        aspectRatio: String? = nil,
        title: String? = nil,
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
            extendedVideoType: extendedVideoType,
            extendedVideoSubTypeDescription: extendedVideoSubTypeDescription,
            bitRate: bitRate,
            bitDepth: bitDepth,
            sampleRate: sampleRate,
            profile: profile,
            averageFrameRate: averageFrameRate,
            aspectRatio: aspectRatio,
            title: title,
            isDefault: isDefault,
            isForced: false,
            isExternal: false,
            isHearingImpaired: isHearingImpaired,
            deliveryURL: nil
        )
    }
}
