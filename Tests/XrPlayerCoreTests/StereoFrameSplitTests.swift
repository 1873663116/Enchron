import XCTest
@testable import XrPlayerCore

final class StereoFrameSplitTests: XCTestCase {
    typealias Stereo = PlaybackCoreDomain.StereoMode

    func testStereoModeHasTwoCasesAndValidUV() {
        XCTAssertEqual(Stereo.allCases.count, 2)
        // Stub leftEyeUVRect is all zeros → FAIL
        let sbsLeft = Stereo.sideBySide.leftEyeUVRect
        XCTAssertGreaterThan(sbsLeft.width, 0,
                             "SBS left eye must have non-zero width")
    }

    func testSBSLeftEyeUVRect() {
        let rect = Stereo.sideBySide.leftEyeUVRect
        // Stub returns all zeros → FAIL
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1.0, accuracy: 0.001)
    }

    func testSBSRightEyeUVRect() {
        let rect = Stereo.sideBySide.rightEyeUVRect
        // Stub returns all zeros → FAIL
        XCTAssertEqual(rect.originX, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1.0, accuracy: 0.001)
    }

    func testOULeftEyeUVRect() {
        let rect = Stereo.overUnder.leftEyeUVRect
        // Stub returns all zeros → FAIL (expected origin=(0,0), size=(1.0, 0.5))
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect.height, 0.5, accuracy: 0.001)
    }

    func testOURightEyeUVRect() {
        let rect = Stereo.overUnder.rightEyeUVRect
        // Stub returns all zeros → FAIL (expected origin=(0, 0.5), size=(1.0, 0.5))
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect.height, 0.5, accuracy: 0.001)
    }

    func testStereoOutputDimensionsSBS() {
        let (w, h) = Stereo.sideBySide.outputDimensions(inputWidth: 3840, inputHeight: 1080)
        // Stub returns (0, 0) → FAIL
        XCTAssertEqual(w, 1920, "SBS output width = input/2")
        XCTAssertEqual(h, 1080, "SBS output height = input height")
    }

    func testStereoOutputDimensionsOU() {
        let (w, h) = Stereo.overUnder.outputDimensions(inputWidth: 1920, inputHeight: 2160)
        // Stub returns (0, 0) → FAIL
        XCTAssertEqual(w, 1920, "OU output width = input width")
        XCTAssertEqual(h, 1080, "OU output height = input/2")
    }
}
