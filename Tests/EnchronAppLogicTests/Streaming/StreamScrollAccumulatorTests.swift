import GameStreaming
import XCTest

nonisolated final class StreamScrollAccumulatorTests: XCTestCase {
    func testFractionalValuesBecomeWholeClicksAndKeepTheRemainder() {
        var accumulator = StreamScrollAccumulator()

        XCTAssertEqual(accumulator.clicks(for: 0.5), 0)
        XCTAssertEqual(accumulator.clicks(for: 0.25), 0)
        XCTAssertEqual(accumulator.clicks(for: 0.5), 1)
        XCTAssertEqual(accumulator.clicks(for: 0.5), 0)
        XCTAssertEqual(accumulator.clicks(for: 0.25), 1)
    }

    func testNegativeDeltasAccumulateTowardNegativeClicks() {
        var accumulator = StreamScrollAccumulator()

        XCTAssertEqual(accumulator.clicks(for: -0.75), 0)
        XCTAssertEqual(accumulator.clicks(for: -0.75), -1)
        XCTAssertEqual(accumulator.clicks(for: -0.5), -1)
    }

    func testWholeDeltasPassThroughUnchanged() {
        var accumulator = StreamScrollAccumulator()

        XCTAssertEqual(accumulator.clicks(for: 3), 3)
        XCTAssertEqual(accumulator.clicks(for: -2), -2)
    }

    func testOppositeHalfTurnsCancelWithoutAClick() {
        var accumulator = StreamScrollAccumulator()

        XCTAssertEqual(accumulator.clicks(for: 0.75), 0)
        XCTAssertEqual(accumulator.clicks(for: -0.75), 0)
        XCTAssertEqual(accumulator.clicks(for: 1), 1)
    }
}
