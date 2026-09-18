import Foundation
@testable import Playback
import Testing

@MainActor
@Suite("Application suspension detection")
struct ApplicationSuspensionWatchdogTests {
    @Test("gaps below the threshold are ordinary scheduling jitter")
    func ordinaryGapsAreNotSuspension() {
        #expect(
            ApplicationSuspensionDetectionPolicy.detectedSuspension(gap: 0)
                == false
        )
        #expect(
            ApplicationSuspensionDetectionPolicy.detectedSuspension(gap: 9.9)
                == false
        )
    }

    @Test("a tick gap at or beyond the threshold reports a suspension")
    func largeGapReportsSuspension() {
        #expect(
            ApplicationSuspensionDetectionPolicy.detectedSuspension(gap: 10)
                == true
        )
        #expect(
            ApplicationSuspensionDetectionPolicy.detectedSuspension(gap: 300)
                == true
        )
    }
}
