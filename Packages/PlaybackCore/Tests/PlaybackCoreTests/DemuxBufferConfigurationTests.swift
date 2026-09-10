import PlaybackFFmpegBridge
import Testing
@testable import PlaybackCore

@Test func demuxBufferEnvironmentOverridesBecomeEffectiveConfiguration() throws {
    let configuration = try PBFFmpegDemuxBufferConfiguration.playbackConfiguration(
        for: .automatic,
        environment: [
            "ENCHRON_DEMUX_FORWARD_BUFFER_BYTES": "262144",
            "ENCHRON_DEMUX_BACKWARD_BUFFER_BYTES": "131072",
            "ENCHRON_DEMUX_CACHE_SECONDS": "12.5"
        ]
    )

    #expect(configuration.mode == PBFFmpegDemuxBufferModeAutomatic)
    #expect(configuration.forwardByteLimit == 262_144)
    #expect(configuration.backwardByteLimit == 131_072)
    #expect(configuration.targetDurationSeconds == 12.5)
}

@Test func explicitBufferDepthOverridesOnlyTheDefaultForwardLimit() throws {
    let configuration = try PBFFmpegDemuxBufferConfiguration.playbackConfiguration(
        for: .bytes(96 * 1_024),
        environment: [:]
    )

    #expect(configuration.mode == PBFFmpegDemuxBufferModeBytes)
    #expect(configuration.forwardByteLimit == 96 * 1_024)
    #expect(configuration.backwardByteLimit == 50 * 1_024 * 1_024)
    #expect(configuration.targetDurationSeconds == 1_000 * 60 * 60)
}

@Test func demuxBufferDiagnosticsExposeMechanicalRegressionFields() {
    var diagnostics = PlaybackDiagnostics()
    diagnostics.demuxBuffer = PlaybackDemuxBufferDiagnostics(
        mode: .automatic,
        bufferedDurationSeconds: 4.25,
        targetDurationSeconds: 3_600_000,
        forwardBufferedBytes: 123_456,
        forwardLimitBytes: 157_286_400,
        auxiliaryBufferedBytes: 4_096,
        backwardBufferedBytes: 0,
        backwardLimitBytes: 52_428_800,
        reconnectAttemptCount: 2,
        readFrameCount: 99
    )

    let text = diagnostics.snapshotText
    #expect(text.contains("mode=automatic"))
    #expect(text.contains("durationSeconds=4.25"))
    #expect(text.contains("targetSeconds=3600000.0"))
    #expect(text.contains("forwardBytes=123456"))
    #expect(text.contains("forwardLimitBytes=157286400"))
    #expect(text.contains("auxiliaryBytes=4096"))
    #expect(text.contains("backwardBytes=0"))
    #expect(text.contains("backwardLimitBytes=52428800"))
    #expect(text.contains("reconnects=2"))
    #expect(text.contains("readFrames=99"))
}
