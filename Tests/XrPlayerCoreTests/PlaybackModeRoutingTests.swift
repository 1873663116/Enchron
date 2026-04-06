import XCTest
@testable import XrPlayerCore

final class PlaybackModeRoutingTests: XCTestCase {
    typealias MP = PlaybackCoreDomain.MediaProfile

    private func makeProfile(_ projection: PlaybackCoreDomain.ProjectionType) -> MP {
        MP(projectionType: projection, hdrType: .sdr,
           resolution: .init(width: 1920, height: 1080))
    }

    func testDecidePlaybackModeUseCaseExistsAndReturnsCorrectly() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.equirectangular360)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: nil)
        XCTAssertEqual(result, .panorama,
                       "equirectangular360 without override should route to .panorama")
    }

    func testDecisionWithManualOverrideToWindow() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.equirectangular360)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .window)
        XCTAssertEqual(result, .window, "Manual override to window must be respected")
        // Also verify that WITHOUT override, panorama routes correctly
        let auto = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                      manualOverride: nil)
        XCTAssertEqual(auto, .panorama,
                       "Without override, equirectangular360 must route to .panorama")
    }

    func testDecisionWithManualOverrideToImmersive() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.flat)
        // Stub returns .window → FAIL (expected .immersive for this override)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .immersive)
        XCTAssertEqual(result, .immersive,
                       "Manual override to immersive must be respected")
    }

    func testDecisionWithNoOverrideFallsBackToAuto() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.flat)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: nil)
        // flat + non-immersive → .window (stub returns .window → PASS)
        XCTAssertEqual(result, .window)
        // But: flat + immersive active → should be .immersive
        let immResult = useCase.decideMode(for: profile, isEnvironmentActive: true,
                                           manualOverride: nil)
        // Stub returns .window → FAIL
        XCTAssertEqual(immResult, .immersive,
                       "flat + active environment should route to .immersive")
    }

    func testDecisionStereoFlatInImmersiveIsImmersive() {
        let useCase = DecidePlaybackModeUseCase()
        // Stereo content is flat projection + non-mono stereoLayout
        let profile = makeProfile(.flat)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: true,
                                        manualOverride: nil)
        XCTAssertEqual(result, .immersive,
                       "Flat (stereo) content in active environment should be immersive")
    }

    func testPlaybackModeManagingProtocolConformance() {
        let useCase = DecidePlaybackModeUseCase()
        let _: any PlaybackModeManaging = useCase
        // Verify protocol method works correctly for panorama
        let profile = makeProfile(.equirectangular360)
        let result = (useCase as PlaybackModeManaging).decideMode(
            for: profile, isEnvironmentActive: false, manualOverride: nil)
        XCTAssertEqual(result, .panorama,
                       "Protocol conformance must correctly route panorama")
    }

    // MARK: - Geometric Constraint: allowedModes(for:)

    func testAllowedModesForFlatContent() {
        let allowed = DecidePlaybackModeUseCase.allowedModes(for: .flat)
        XCTAssertEqual(allowed, [.window, .immersive],
                       "Flat content should allow window and immersive only")
        XCTAssertFalse(allowed.contains(.panorama),
                       "Flat content must not allow panorama mode")
    }

    func testAllowedModesForStereoContent() {
        // Stereo SBS is now flat projection + sideBySide StereoLayout
        let allowed = DecidePlaybackModeUseCase.allowedModes(for: .flat)
        XCTAssertEqual(allowed, [.window, .immersive],
                       "Flat (stereo) content should allow window and immersive only")
    }

    func testAllowedModesForPanoramicContent() {
        let allowed = DecidePlaybackModeUseCase.allowedModes(for: .equirectangular360)
        XCTAssertEqual(allowed, [.window, .immersive, .panorama],
                       "Panoramic content should allow all three modes")
    }

    func testAllowedModesForNilProjectionType() {
        let allowed = DecidePlaybackModeUseCase.allowedModes(for: nil)
        XCTAssertEqual(allowed, [.window, .immersive],
                       "Nil projection (not yet detected) should default to window and immersive")
    }

    // MARK: - Geometric Constraint: Manual Override Clamping

    func testManualOverrideToPanoramaForFlatContentIsClamped() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.flat)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .panorama)
        XCTAssertEqual(result, .window,
                       "Panorama override for flat content must be clamped to window")
    }

    func testManualOverrideToPanoramaForStereoFlatContentIsClamped() {
        let useCase = DecidePlaybackModeUseCase()
        // Stereo content uses flat projection now
        let profile = makeProfile(.flat)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .panorama)
        XCTAssertEqual(result, .window,
                       "Panorama override for flat/stereo content must be clamped to window")
    }

    func testManualOverrideToPanoramaForPanoramicContentIsAllowed() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.equirectangular360)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .panorama)
        XCTAssertEqual(result, .panorama,
                       "Panorama override for panoramic content must be allowed")
    }

    func testManualOverrideToImmersiveForFlatContentIsAllowed() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.flat)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .immersive)
        XCTAssertEqual(result, .immersive,
                       "Immersive override for flat content must be allowed (virtual cinema)")
    }
}
