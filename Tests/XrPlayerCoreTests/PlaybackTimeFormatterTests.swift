import XCTest

@testable import XrPlayerCore

final class PlaybackTimeFormatterTests: XCTestCase {
    func testClockOmitsHoursForShortDurations() {
        XCTAssertEqual(PlaybackTimeFormatter.clock(65), "01:05")
    }

    func testClockIncludesHoursWhenNeeded() {
        XCTAssertEqual(PlaybackTimeFormatter.clock(3665), "1:01:05")
    }

    func testPreciseClockIncludesFramesWhenFrameRateIsKnown() {
        XCTAssertEqual(
            PlaybackTimeFormatter.preciseClock(3665.5, framesPerSecond: 24),
            "01:01:05.12"
        )
    }

    func testPreciseClockFallsBackToWholeSecondsWithoutFrameRate() {
        XCTAssertEqual(
            PlaybackTimeFormatter.preciseClock(3665.5, framesPerSecond: 0),
            "01:01:05"
        )
    }
}
