import CoreGraphics
@testable import Playback
import Testing

@MainActor
@Suite("Playback surface seek feedback")
struct PlaybackSurfaceSeekFeedbackTests {
    @Test("selected offset stays under the fixed central playhead")
    func centeredPlayhead() {
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: 0, selectedOffsetSeconds: 0) == 160)
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: 18, selectedOffsetSeconds: 18) == 160)
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: -8, selectedOffsetSeconds: -8) == 160)
        #expect(abs(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: 0, selectedOffsetSeconds: 18) - 73.6) < 0.0001)
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: 30, selectedOffsetSeconds: 30) == 160)
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: -30, selectedOffsetSeconds: -30) == 160)
    }

    @Test("ticks stop at the reachable media boundaries")
    func reachableBoundaries() {
        #expect(PlaybackSurfaceSeekFeedbackGeometry.ticks(in: -6...30, interval: 5) == [-5, 0, 5, 10, 15, 20, 25, 30])
        #expect(PlaybackSurfaceSeekFeedbackGeometry.ticks(in: -30...6, interval: 10) == [-30, -20, -10, 0])
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: -6, selectedOffsetSeconds: -6) == 160)
        #expect(PlaybackSurfaceSeekFeedbackGeometry.position(offsetSeconds: 6, selectedOffsetSeconds: 6) == 160)
    }

    @Test("offset readout uses the fixed uppercase seconds unit")
    func secondsUnit() {
        #expect(PlaybackSurfaceSeekFeedbackGeometry.signedOffset(18) == "+18 S")
        #expect(PlaybackSurfaceSeekFeedbackGeometry.signedOffset(-8) == "−8 S")
        #expect(PlaybackSurfaceSeekFeedbackGeometry.signedOffset(0) == "+0 S")
    }
}
