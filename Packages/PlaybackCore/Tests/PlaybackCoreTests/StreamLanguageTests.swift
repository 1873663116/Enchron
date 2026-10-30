import Foundation
import Testing
@testable import PlaybackCore

@Test func discStreamLanguagesFillStreamsWithoutTheirOwn() {
    let information = MediaSourceInformation(
        containerFormat: "mpegts",
        durationSeconds: 8862,
        streams: [
            MediaSourceStreamInformation(
                streamIndex: 1,
                streamID: 4352,
                category: .audio,
                codecID: 0,
                codecName: "dts",
                codecTag: 0,
                language: nil,
                title: nil,
                disposition: 0,
                video: nil,
                audio: MediaSourceAudioInformation(sampleRate: 48000, channelCount: 8)
            ),
            MediaSourceStreamInformation(
                streamIndex: 2,
                streamID: 4353,
                category: .audio,
                codecID: 0,
                codecName: "ac3",
                codecTag: 0,
                language: "deu",
                title: nil,
                disposition: 0,
                video: nil,
                audio: MediaSourceAudioInformation(sampleRate: 48000, channelCount: 2)
            ),
            MediaSourceStreamInformation(
                streamIndex: 0,
                streamID: 4113,
                category: .video,
                codecID: 0,
                codecName: "h264",
                codecTag: 0,
                language: nil,
                title: nil,
                disposition: 0,
                video: nil,
                audio: nil
            )
        ]
    )

    let filled = information.fillingStreamLanguages([4352: "eng", 4353: "fra", 4113: "eng"])

    #expect(filled.streams[0].language == "eng")
    #expect(filled.streams[1].language == "deu")
    #expect(filled.streams[2].language == nil)
}

@Test func audioAndSubtitleLabelsUseLocalizedLanguageNames() {
    let audio = PlaybackAudioTrack(
        streamIndex: 2,
        codecName: "ac3",
        sampleRate: 48000,
        channelCount: 2,
        language: "eng",
        title: nil
    )
    #expect(audio.label == "English · ac3 · 2ch")

    let unnamed = PlaybackAudioTrack(
        streamIndex: 5,
        codecName: "ac3",
        sampleRate: 48000,
        channelCount: 6,
        language: nil,
        title: nil
    )
    #expect(unnamed.label == "Track 5 · ac3 · 6ch")

    let subtitle = PlaybackSubtitleTrack(
        id: "subtitle.6",
        streamIndex: 6,
        codecName: "hdmv_pgs_subtitle",
        language: "fra",
        title: nil
    )
    #expect(subtitle.label == "French")
}

@Test func unknownLanguageCodesFallBackToTheCode() {
    #expect(PlaybackLanguageName.display("und") == nil)
    #expect(PlaybackLanguageName.display("") == nil)
    #expect(PlaybackLanguageName.display("xyz") == "XYZ")
}
