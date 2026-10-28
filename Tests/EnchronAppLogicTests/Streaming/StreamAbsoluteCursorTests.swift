import GameStreaming
import XCTest

nonisolated final class StreamAbsoluteCursorTests: XCTestCase {
    func testTheCursorStartsAtTheMiddleOfThePicture() {
        var cursor = StreamAbsoluteCursor()

        let position = cursor.position(rawDeltaX: 0, rawDeltaY: 0, width: 1920, height: 1080)

        XCTAssertNil(position)
        let moved = cursor.position(rawDeltaX: 1.25, rawDeltaY: 0, width: 1920, height: 1080)
        XCTAssertEqual(moved?.x ?? 0, 0.5 + 1.0 / 1920, accuracy: 0.000_001)
        XCTAssertEqual(moved?.y ?? 0, 0.5, accuracy: 0.000_001)
    }

    func testVerticalDeviceMotionMovesTheCursorDown() {
        var cursor = StreamAbsoluteCursor()

        let position = cursor.position(rawDeltaX: 0, rawDeltaY: 135, width: 1920, height: 1080)

        XCTAssertEqual(position?.y ?? 0, 0.5 + 0.1, accuracy: 0.01)
    }

    func testSubPixelMotionAccumulatesInsteadOfVanishing() {
        var cursor = StreamAbsoluteCursor()

        XCTAssertNil(cursor.position(rawDeltaX: 0.7, rawDeltaY: 0, width: 1920, height: 1080))
        let moved = cursor.position(rawDeltaX: 0.7, rawDeltaY: 0, width: 1920, height: 1080)
        XCTAssertEqual(moved?.x ?? 0, 0.5 + 1.0 / 1920, accuracy: 0.000_001)
    }

    func testTheCursorStaysInsideThePicture() {
        var cursor = StreamAbsoluteCursor()

        let right = cursor.position(rawDeltaX: 1_000_000, rawDeltaY: 1_000_000,
                                    width: 1920, height: 1080)
        XCTAssertEqual(right?.x, 1)
        XCTAssertEqual(right?.y, 1)

        let left = cursor.position(rawDeltaX: -2_000_000, rawDeltaY: -2_000_000,
                                   width: 1920, height: 1080)
        XCTAssertEqual(left?.x, 0)
        XCTAssertEqual(left?.y, 0)
    }

    func testResetReturnsTheCursorToTheMiddle() {
        var cursor = StreamAbsoluteCursor()
        _ = cursor.position(rawDeltaX: 1_000, rawDeltaY: 1_000, width: 1920, height: 1080)

        cursor.reset()
        let position = cursor.position(rawDeltaX: 0, rawDeltaY: 0, width: 1920, height: 1080)

        XCTAssertNil(position)
        let moved = cursor.position(rawDeltaX: 1.25, rawDeltaY: 0, width: 1920, height: 1080)
        XCTAssertEqual(moved?.x ?? 0, 0.5 + 1.0 / 1920, accuracy: 0.000_001)
    }

    func testAnEmptyPictureProducesNoPosition() {
        var cursor = StreamAbsoluteCursor()

        XCTAssertNil(cursor.position(rawDeltaX: 100, rawDeltaY: 100, width: 0, height: 0))
    }
}
