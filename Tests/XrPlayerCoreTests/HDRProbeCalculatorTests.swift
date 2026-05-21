import Testing
@testable import XrPlayerCore

@Suite("HDRProbeCalculator")
struct HDRProbeCalculatorTests {
    @Test("computes max, averages, percentiles, and threshold counts")
    func computesStatistics() {
        let pixels: [PlaybackCoreDomain.HDRProbeCalculator.Pixel] = [
            .init(red: 0.5, green: 0.5, blue: 0.5),
            .init(red: 1.0, green: 1.0, blue: 1.0),
            .init(red: 2.0, green: 2.0, blue: 2.0),
            .init(red: 4.0, green: 4.0, blue: 4.0)
        ]

        let stats = PlaybackCoreDomain.HDRProbeCalculator.statistics(for: pixels)

        #expect(stats.maxRGB.maxChannel == 4.0)
        #expect(stats.averageRGB.red == 1.875)
        #expect(abs(stats.p99Luminance - 4.0) < 0.000_001)
        #expect(abs(stats.p95Luminance - 4.0) < 0.000_001)
        #expect(stats.countAbove1 == 2)
        #expect(stats.countAbove2 == 1)
        #expect(stats.sampledPixelCount == 4)
    }

    @Test("computes ON/OFF delta from recent probe samples")
    func computesDelta() {
        let off = sample(max: 1.0, p99: 0.9, above1: 0, above2: 0, enabled: false)
        let on = sample(max: 4.0, p99: 2.5, above1: 20, above2: 6, enabled: true)

        let delta = PlaybackCoreDomain.HDRProbeDelta(onSample: on, offSample: off)

        #expect(delta.maxRGBDelta == 3.0)
        #expect(delta.p99LuminanceDelta == 1.6)
        #expect(delta.countAbove1Delta == 20)
        #expect(delta.countAbove2Delta == 6)
    }

    @Test("rejects ON/OFF delta across different media or time")
    func rejectsMismatchedDelta() {
        let off = sample(max: 1.0, p99: 0.9, above1: 0, above2: 0, enabled: false, time: 10)
        let otherFile = sample(
            max: 4.0,
            p99: 2.5,
            above1: 20,
            above2: 6,
            enabled: true,
            media: "file-b",
            time: 10
        )
        let otherTime = sample(max: 4.0, p99: 2.5, above1: 20, above2: 6, enabled: true, time: 14)

        #expect(PlaybackCoreDomain.HDRProbeDelta.matching(onSample: otherFile, offSample: off) == nil)
        #expect(PlaybackCoreDomain.HDRProbeDelta.matching(onSample: otherTime, offSample: off) == nil)
    }

    @Test("marks boundary values at one and two as not above threshold")
    func thresholdBoundariesAreExclusive() {
        let pixels: [PlaybackCoreDomain.HDRProbeCalculator.Pixel] = [
            .init(red: 1.0, green: 1.0, blue: 1.0),
            .init(red: 2.0, green: 2.0, blue: 2.0)
        ]

        let stats = PlaybackCoreDomain.HDRProbeCalculator.statistics(for: pixels)

        #expect(stats.countAbove1 == 1)
        #expect(stats.countAbove2 == 0)
    }

    private func sample(
        max: Double,
        p99: Double,
        above1: Int,
        above2: Int,
        enabled: Bool,
        media: String = "file-a",
        time: Double? = 12
    ) -> PlaybackCoreDomain.HDRProbeSample {
        PlaybackCoreDomain.HDRProbeSample(
            source: .mpvDrawable,
            hdrOutputEnabled: enabled,
            pixelFormat: "rgba16Float",
            colorspace: "kCGColorSpaceExtendedLinearDisplayP3",
            width: 2,
            height: 2,
            statistics: PlaybackCoreDomain.HDRProbeStatistics(
                maxRGB: .init(red: max, green: max, blue: max),
                averageRGB: .init(red: 0, green: 0, blue: 0),
                p99Luminance: p99,
                p95Luminance: p99,
                countAbove1: above1,
                countAbove2: above2,
                sampledPixelCount: 4
            ),
            videoTime: time,
            contract: PlaybackCoreDomain.HDRProbeContract.extendedLinearDisplayP3.rawValue,
            mediaFingerprint: media,
            renderer: "mpv",
            probeRegion: "center 640x640 @ 0,0",
            sampleSequence: 1
        )
    }
}
