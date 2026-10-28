import GameStreaming
import XCTest

nonisolated final class StreamMouseMotionTests: XCTestCase {
    func testHorizontalMotionKeepsItsDirectionAndVerticalMotionReverses() {
        var right = StreamMouseMotion()
        let rightward = right.screenDelta(rawX: 25, rawY: 0)
        XCTAssertEqual(rightward.x, 20)
        XCTAssertEqual(rightward.y, 0)

        var down = StreamMouseMotion()
        let downward = down.screenDelta(rawX: 0, rawY: 25)
        XCTAssertEqual(downward.x, 0)
        XCTAssertEqual(downward.y, -20)
    }

    func testSubPixelMotionAccumulatesInsteadOfVanishing() {
        var motion = StreamMouseMotion()

        XCTAssertEqual(motion.screenDelta(rawX: 0.5, rawY: 0).x, 0)
        XCTAssertEqual(motion.screenDelta(rawX: 0.5, rawY: 0).x, 0)
        XCTAssertEqual(motion.screenDelta(rawX: 0.5, rawY: 0).x, 1)
    }

    func testFractionalRemainderSurvivesAcrossEvents() {
        var motion = StreamMouseMotion()

        XCTAssertEqual(motion.screenDelta(rawX: 0, rawY: 10).y, -8)
        XCTAssertEqual(motion.screenDelta(rawX: 0, rawY: 10).y, -8)
        XCTAssertEqual(motion.screenDelta(rawX: 0, rawY: 1).y, 0)
        XCTAssertEqual(motion.screenDelta(rawX: 0, rawY: 4).y, -4)
    }

    func testZeroMotionSendsNothing() {
        var motion = StreamMouseMotion()
        let delta = motion.screenDelta(rawX: 0, rawY: 0)

        XCTAssertEqual(delta.x, 0)
        XCTAssertEqual(delta.y, 0)
    }
}
