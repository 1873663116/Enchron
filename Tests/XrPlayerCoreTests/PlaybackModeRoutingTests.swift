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
        let profile = makeProfile(.panorama360)
        // Stub always returns .window → FAIL for panorama input
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: nil)
        XCTAssertEqual(result, .panorama,
                       "panorama360 without override should route to .panorama")
    }

    func testDecisionWithManualOverrideToWindow() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.panorama360)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                        manualOverride: .window)
        // Stub returns .window → this WOULD pass, but let's also check non-override
        // The contract says override takes precedence:
        XCTAssertEqual(result, .window, "Manual override to window must be respected")
        // Also verify that WITHOUT override, panorama routes correctly
        let auto = useCase.decideMode(for: profile, isEnvironmentActive: false,
                                      manualOverride: nil)
        // Stub returns .window → FAIL
        XCTAssertEqual(auto, .panorama,
                       "Without override, panorama360 must route to .panorama")
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

    func testDecisionStereo3DInImmersiveIsImmersive() {
        let useCase = DecidePlaybackModeUseCase()
        let profile = makeProfile(.stereoscopicSBS)
        // Stub returns .window → FAIL (expected .immersive when environment active)
        let result = useCase.decideMode(for: profile, isEnvironmentActive: true,
                                        manualOverride: nil)
        XCTAssertEqual(result, .immersive,
                       "Stereo SBS in active environment should be immersive")
    }

    func testPlaybackModeManagingProtocolConformance() {
        let useCase = DecidePlaybackModeUseCase()
        let _: any PlaybackModeManaging = useCase
        // Verify protocol method works correctly for panorama
        let profile = makeProfile(.panorama360)
        let result = (useCase as PlaybackModeManaging).decideMode(
            for: profile, isEnvironmentActive: false, manualOverride: nil)
        // Stub returns .window → FAIL
        XCTAssertEqual(result, .panorama,
                       "Protocol conformance must correctly route panorama")
    }
}
