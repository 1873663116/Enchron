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
        // Current impl: "fisheye" doesn't match "equirectangular" or "cubemap"
        // but isSpherical=true → falls through to panorama360 → FAIL (expected .fisheye)
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
        // Current impl: doesn't match → returns .panorama360 → FAIL
        XCTAssertEqual(result, .fisheye,
                       "GSpherical 'equidistant_fisheye' must detect as .fisheye")
    }

    func testProjectionTypeIsStereo3D() {
        // These computed properties don't exist yet → need to add stubs
        // For now test that the cases we expect to be stereo are correct
        let stereoTypes: [PlaybackCoreDomain.ProjectionType] = [.stereoscopicSBS, .stereoscopicOU]
        let nonStereoTypes: [PlaybackCoreDomain.ProjectionType] = [.flat, .panorama360, .panorama180, .fisheye]

        for t in stereoTypes {
            XCTAssertTrue(t.isStereo3D, "\(t) must be stereo 3D")
        }
        for t in nonStereoTypes {
            XCTAssertFalse(t.isStereo3D, "\(t) must not be stereo 3D")
        }
    }

    func testProjectionTypeRequiresHemisphereMesh() {
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.panorama180.requiresHemisphereMesh,
                      "panorama180 must require hemisphere mesh")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.panorama360.requiresHemisphereMesh,
                       "panorama360 must not require hemisphere mesh")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.flat.requiresHemisphereMesh,
                       "flat must not require hemisphere mesh")
    }

    func testProjectionTypeRequiresFisheyeRemap() {
        XCTAssertTrue(PlaybackCoreDomain.ProjectionType.fisheye.requiresFisheyeRemap,
                      "fisheye must require remap")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.panorama360.requiresFisheyeRemap,
                       "panorama360 must not require remap")
        XCTAssertFalse(PlaybackCoreDomain.ProjectionType.flat.requiresFisheyeRemap,
                       "flat must not require remap")
    }
}
