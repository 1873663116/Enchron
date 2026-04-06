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
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .fisheye,
                       "GSpherical projectionType 'fisheye' must detect as .fisheye")
        XCTAssertEqual(stereo, .mono,
                       "Fisheye projection must force stereoLayout to .mono")
    }

    func testFisheyeDetectionFromEquidistantTag() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "equidistant_fisheye",
            horizontalFOVDegrees: nil,
            aspectRatio: 1.0
        )
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .fisheye,
                       "GSpherical 'equidistant_fisheye' must detect as .fisheye")
        XCTAssertEqual(stereo, .mono,
                       "Fisheye projection must force stereoLayout to .mono")
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
        let (projection, _) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .equirectangular360,
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
        let (projection, _) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .equirectangular180,
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
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .flat,
                       "No metadata markers must detect as .flat")
        XCTAssertEqual(stereo, .mono,
                       "No stereo metadata must detect as .mono")
    }

    // MARK: - Unit 3: Stereo layout detection tests

    func testStereoSBS2LDetectsAsSideBySide() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "sbs2l",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 2.0
        )
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .flat, "SBS content without spherical metadata must be flat")
        XCTAssertEqual(stereo, .sideBySide, "sbs2l must detect as .sideBySide")
    }

    func testStereoSBS2RDetectsAsSideBySide() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "sbs2r",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 2.0
        )
        let (_, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(stereo, .sideBySide, "sbs2r must detect as .sideBySide")
    }

    func testStereoAB2RDetectsAsTopBottom() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "ab2r",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 1.0
        )
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .flat, "TB content without spherical metadata must be flat")
        XCTAssertEqual(stereo, .topBottom, "ab2r must detect as .topBottom")
    }

    func testStereoAB2LDetectsAsTopBottom() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "ab2l",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 1.0
        )
        let (_, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(stereo, .topBottom, "ab2l must detect as .topBottom")
    }

    func testStereoMonoDetectsAsMono() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "mono",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 1.78
        )
        let (_, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(stereo, .mono, "'mono' stereo3d value must detect as .mono")
    }

    func testStereoEmptyStringDetectsAsMono() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 1.78
        )
        let (_, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(stereo, .mono, "Empty stereo3d string must detect as .mono")
    }

    func testStereoNoValueDetectsAsMono() {
        let input = ProjectionDetectionInput(
            stereo3dIn: "no",
            gSphericalSpherical: nil,
            gSphericalProjectionType: nil,
            horizontalFOVDegrees: nil,
            aspectRatio: 1.78
        )
        let (_, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(stereo, .mono, "'no' stereo3d value must detect as .mono")
    }

    /// Dead code verification: legacy string formats never output by mpv must fall through to .mono.
    func testDeadCodeLegacyStereoStringsDetectAsMono() {
        let deadValues = ["side_by_side_left", "over_under_left", "top_bottom", "over_under"]
        for value in deadValues {
            let input = ProjectionDetectionInput(
                stereo3dIn: value,
                gSphericalSpherical: nil,
                gSphericalProjectionType: nil,
                horizontalFOVDegrees: nil,
                aspectRatio: nil
            )
            let (_, stereo) = ProjectionDetection.detect(from: input)
            XCTAssertEqual(stereo, .mono,
                           "Dead-code value '\(value)' (never output by mpv) must fall through to .mono")
        }
    }

    func testSBSWithSphericalMetadataPreservesSphericalProjection() {
        // stereo3dIn = "sbs2l" + spherical → projection overridden by GSpherical,
        // stereoLayout from stereo3d tag.
        let input = ProjectionDetectionInput(
            stereo3dIn: "sbs2l",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "equirectangular",
            horizontalFOVDegrees: nil,
            aspectRatio: 2.0
        )
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .equirectangular360,
                       "GSpherical equirectangular must override projection even with stereo tag")
        XCTAssertEqual(stereo, .sideBySide,
                       "sbs2l stereo tag must carry through to StereoLayout")
    }

    func testFisheyeWithSBSTagForcesMonoStereo() {
        // Even if stereo3d says SBS, fisheye projection forces stereoLayout = .mono.
        let input = ProjectionDetectionInput(
            stereo3dIn: "sbs2l",
            gSphericalSpherical: "true",
            gSphericalProjectionType: "fisheye",
            horizontalFOVDegrees: nil,
            aspectRatio: 1.0
        )
        let (projection, stereo) = ProjectionDetection.detect(from: input)
        XCTAssertEqual(projection, .fisheye,
                       "Fisheye GSpherical must detect as .fisheye")
        XCTAssertEqual(stereo, .mono,
                       "Fisheye must force stereoLayout to .mono regardless of stereo3d tag")
    }
}
