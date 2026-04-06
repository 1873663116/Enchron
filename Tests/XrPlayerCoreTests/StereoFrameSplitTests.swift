import XCTest
@testable import XrPlayerCore

final class StereoFrameSplitTests: XCTestCase {
    typealias Stereo = PlaybackCoreDomain.StereoLayout

    func testStereoLayoutHasThreeCasesAndValidUV() {
        XCTAssertEqual(Stereo.allCases.count, 3)
        let sbsLeft = Stereo.sideBySide.leftEyeUVRect
        XCTAssertGreaterThan(sbsLeft.width, 0,
                             "SBS left eye must have non-zero width")
    }

    func testMonoLeftEyeUVRectIsFullFrame() {
        let rect = Stereo.mono.leftEyeUVRect
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1.0, accuracy: 0.001)
    }

    func testMonoOutputDimensionsUnchanged() {
        let (w, h) = Stereo.mono.outputDimensions(inputWidth: 1920, inputHeight: 1080)
        XCTAssertEqual(w, 1920, "Mono output width = input width")
        XCTAssertEqual(h, 1080, "Mono output height = input height")
    }

    func testSBSLeftEyeUVRect() {
        let rect = Stereo.sideBySide.leftEyeUVRect
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1.0, accuracy: 0.001)
    }

    func testSBSRightEyeUVRect() {
        let rect = Stereo.sideBySide.rightEyeUVRect
        XCTAssertEqual(rect.originX, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1.0, accuracy: 0.001)
    }

    func testTopBottomLeftEyeUVRect() {
        let rect = Stereo.topBottom.leftEyeUVRect
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect.height, 0.5, accuracy: 0.001)
    }

    func testTopBottomRightEyeUVRect() {
        let rect = Stereo.topBottom.rightEyeUVRect
        XCTAssertEqual(rect.originX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.originY, 0.5, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(rect.height, 0.5, accuracy: 0.001)
    }

    func testStereoOutputDimensionsSBS() {
        let (w, h) = Stereo.sideBySide.outputDimensions(inputWidth: 3840, inputHeight: 1080)
        XCTAssertEqual(w, 1920, "SBS output width = input/2")
        XCTAssertEqual(h, 1080, "SBS output height = input height")
    }

    func testStereoOutputDimensionsTopBottom() {
        let (w, h) = Stereo.topBottom.outputDimensions(inputWidth: 1920, inputHeight: 2160)
        XCTAssertEqual(w, 1920, "TopBottom output width = input width")
        XCTAssertEqual(h, 1080, "TopBottom output height = input/2")
    }
}
