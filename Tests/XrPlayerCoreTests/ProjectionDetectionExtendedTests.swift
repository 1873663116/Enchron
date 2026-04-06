import XCTest
@testable import XrPlayerCore

final class ProjectionDetectionExtendedTests: XCTestCase {

    func testFisheyeDetectionFromGSphericalProjection() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "fisheye",
            horizontalFOVDegrees: nil,
            aspectRatio: 1.0
        )
        let result = ProjectionDetection.detect(from: input)
        XCTAssertEqual(result, .fisheye,
                       "GSpherical projectionType 'fisheye' must detect as .fisheye")
    }

    func testFisheyeDetectionFromEquidistantTag() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "equidistant_fisheye",
            horizontalFOVDegrees: nil,
            aspectRatio: 1.0
        )
        let result = ProjectionDetection.detect(from: input)
        XCTAssertEqual(result, .fisheye,
                       "GSpherical 'equidistant_fisheye' must detect as .fisheye")
    }

    func testProjectionTypeRequiresHemisphereMesh() {
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.equirectangular180.requiresHemisphereMesh,
                      "equirectangular180 must require hemisphere mesh")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.equirectangular360.requiresHemisphereMesh,
                       "equirectangular360 must not require hemisphere mesh")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.flat.requiresHemisphereMesh,
                       "flat must not require hemisphere mesh")
    }

    func testProjectionTypeRequiresFisheyeRemap() {
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.fisheye.requiresFisheyeRemap,
                      "fisheye must require remap")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.equirectangular360.requiresFisheyeRemap,
                       "equirectangular360 must not require remap")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.flat.requiresFisheyeRemap,
                       "flat must not require remap")
    }

    func testEquirectangular360Detection() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "equirectangular",
            horizontalFOVDegrees: nil,
            aspectRatio: 2.0
        )
        let result = ProjectionDetection.detect(from: input)
        XCTAssertEqual(result, .equirectangular360,
                       "GSpherical equirectangular without FOV limit should detect as .equirectangular360")
    }

    func testEquirectangular180DetectionFrom180FOV() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "equirectangular",
            horizontalFOVDegrees: 180,
            aspectRatio: 1.0
        )
        let result = ProjectionDetection.detect(from: input)
        XCTAssertEqual(result, .equirectangular180,
                       "GSpherical equirectangular with 180° FOV must detect as .equirectangular180")
    }

    func testFlatDetectionWithNoMetadata() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 1.78
        )
        let result = ProjectionDetection.detect(from: input)
        XCTAssertEqual(result, .flat,
                       "No metadata markers must detect as .flat")
    }
}
