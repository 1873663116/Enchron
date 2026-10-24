import EnvironmentSceneContract
import Foundation
import AVFoundation
#if os(visionOS)
import AVKit
import UIKit
#endif
@testable import Playback
import Testing
@testable import Enchron

@MainActor
struct EnvironmentSceneMappingTests {

    @Test("the catalog exposes the scene-backed card environments")
    func catalogUsesAuthoredScenes() {
        #expect(FeaturedEnvironment.catalog.map(\.environment) == [.ocean, .tidal])
        #expect(FeaturedEnvironment.catalog.map(\.id) == ["ocean", "tidal"])
        #expect(SpatialSceneDomain.CinemaEnvironment.cardEnvironments == [.ocean, .tidal])
        #expect(SpatialSceneDomain.EnvironmentEffect.allCases == [.light, .dark])
    }

    @Test("Quiet Room is the only environment without dark appearance")
    func quietRoomHasNoDarkAppearance() {
        for environment in SpatialSceneDomain.CinemaEnvironment.allCases {
            #expect(
                environment.supportsDarkAppearance == (environment != .quietRoom),
                "\(environment) must support dark appearance unless it is Quiet Room"
            )
            #expect(
                environment.isCardEnvironment == (environment != .quietRoom),
                "\(environment) must be a card environment unless it is Quiet Room"
            )
        }
    }

    @Test("each environment identity resolves to the geometry authored for its scene")
    func descriptorGeometryMatchesEachEnvironment() {
        let ocean = EnvironmentSceneMapping.geometry(for: .ocean)
        #expect(ocean.distanceRangeMeters == 12...47)
        #expect(ocean.defaultDistanceMeters == 30)
        #expect(ocean.viewerHeightRangeMeters == -3...5)
        #expect(ocean.defaultViewerHeightMeters == 1)
        #expect(ocean.elevationRangeDegrees == 0...90)
        #expect(ocean.screenHeightRangeMeters == 20...20)
        #expect(ocean.defaultScreenHeightMeters == 20)
        #expect(ocean.distanceStrategy == .movesViewer)
        #expect(ocean.ceilingHeightMeters == nil)

        let tidal = EnvironmentSceneMapping.geometry(for: .tidal)
        #expect(tidal.distanceRangeMeters == 13.550063...13.550063)
        #expect(tidal.defaultDistanceMeters == 13.550063)
        #expect(tidal.elevationRangeDegrees == 0...90)
        #expect(tidal.screenHeightRangeMeters == 8...8)
        #expect(tidal.defaultScreenHeightMeters == 8)

        let quietRoom = EnvironmentSceneMapping.geometry(for: .quietRoom)
        #expect(quietRoom.distanceRangeMeters == 5...18)
        #expect(quietRoom.defaultDistanceMeters == 12)
        #expect(quietRoom.defaultViewerHeightMeters == 0.5)
        #expect(quietRoom.viewerHeightRangeMeters == -1...3)
        #expect(quietRoom.elevationRangeDegrees == 0...90)
        #expect(quietRoom.screenHeightRangeMeters == 8...8)
        #expect(quietRoom.defaultScreenHeightMeters == 8)
        #expect(quietRoom.distanceStrategy == .movesViewer)
        #expect(quietRoom.ceilingHeightMeters == 7.75)

        #expect(EnvironmentSceneMapping.descriptor(for: .quietRoom).supportsDarkAppearance == false)
        #expect(EnvironmentSceneMapping.descriptor(for: .ocean).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .tidal).supportsDarkAppearance == true)
    }

    @Test("environment IDs resolve their screen heights with the fallback")
    func environmentIDsResolveScreenHeights() {
        for environment in SpatialSceneDomain.CinemaEnvironment.allCases {
            #expect(
                EnvironmentSceneMapping.defaultScreenHeightMeters(
                    forEnvironmentID: environment.rawValue
                ) == (environment == .ocean ? 20 : 8)
            )
        }
        #expect(
            EnvironmentSceneMapping.defaultScreenHeightMeters(forEnvironmentID: "not-a-real-environment")
                == 8
        )
    }

    @Test("Tidal clamps saved and requested translations while preserving pitch control")
    func tidalLocksTranslation() async throws {
        let suite = "EnvironmentSceneMappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite)
        await store.savePosition(
            for: "tidal", distanceMeters: 20, elevationDegrees: 25,
            screenScale: 8, viewerHeightMeters: 1
        )
        let model = PlaybackPresentationModel(screenPositionStore: store, environmentDefaults: defaults)
        try model.activateEnvironment(.tidal, effect: .light)
        await model.loadDockedPlacement()
        #expect(model.dockedPlacement.distanceMeters == 13.550063)
        #expect(model.dockedPlacement.viewerHeightMeters == 0)
        #expect(model.dockedPlacement.elevationDegrees == 25)
        #expect(model.dockedPlacement.limits.distanceRange == 13.550063...13.550063)
        #expect(model.dockedPlacement.limits.viewerHeightRange == 0...0)

        model.setScreenDistance(6)
        model.setViewerHeight(-2)
        model.setScreenElevation(35)
        #expect(model.dockedPlacement.distanceMeters == 13.550063)
        #expect(model.dockedPlacement.viewerHeightMeters == 0)
        #expect(model.dockedPlacement.elevationDegrees == 35)

        model.resetDockedPlacement()
        #expect(model.dockedPlacement.distanceMeters == 13.550063)
        #expect(model.dockedPlacement.viewerHeightMeters == 0)
        #expect(model.dockedPlacement.elevationDegrees == 0)
    }

    @Test(
        "fresh placement and reset use the environment's displayed defaults",
        arguments: [SpatialSceneDomain.CinemaEnvironment.quietRoom, .ocean]
    )
    func freshPlacementAndResetUseEnvironmentDefaults(
        environment: SpatialSceneDomain.CinemaEnvironment
    ) async throws {
        let suite = "EnvironmentSceneMappingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlaybackPresentationModel(
            screenPositionStore: PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite),
            environmentDefaults: defaults
        )
        try model.activateEnvironment(environment, effect: .light)
        await model.loadDockedPlacement()
        let initial = model.dockedPlacement
        let expectedDistance: Double = environment == .quietRoom ? 12 : 30
        let expectedViewerHeight: Double = environment == .quietRoom ? 0.5 : 1
        let expectedDisplayedDistance: Double = environment == .quietRoom ? 7 : 18
        let expectedDisplayedViewerHeight: Double = environment == .quietRoom ? 1.5 : 4

        model.setScreenDistance(15)
        model.setViewerHeight(2)
        #expect(model.dockedPlacement.distanceMeters == 15)
        #expect(model.dockedPlacement.viewerHeightMeters == 2)
        model.resetDockedPlacement()

        for placement in [initial, model.dockedPlacement] {
            let distanceDisplay = placement.distanceMeters - placement.limits.distanceRange.lowerBound
            let heightDisplay = placement.viewerHeightMeters - placement.limits.viewerHeightRange.lowerBound
            #expect(placement.distanceMeters == expectedDistance)
            #expect(placement.viewerHeightMeters == expectedViewerHeight)
            #expect(distanceDisplay == expectedDisplayedDistance)
            #expect(heightDisplay == expectedDisplayedViewerHeight)
            let pose = PlaybackDockedPoseSolver.solve(
                transform: PlaybackSurfaceTransform(
                    distance: placement.distanceMeters,
                    elevationDegrees: placement.elevationDegrees,
                    scale: placement.screenScale,
                    viewerHeight: placement.viewerHeightMeters
                ),
                geometry: EnvironmentSceneMapping.geometry(for: environment),
                restPose: EnvironmentScreenRestPose(
                    center: [0, 4, -8],
                    right: [1, 0, 0],
                    up: [0, 1, 0],
                    normal: [0, 0, 1],
                    halfWidth: 4,
                    halfHeight: 4
                ),
                meshSize: [16, 9]
            )
            #expect(pose.effectiveDistance == Float(expectedDistance))
            #expect(pose.roomPosition.y == (environment == .quietRoom ? -0.5 : -1))
        }
    }
}

@MainActor
struct DefaultCardEnvironmentTests {
    @Test("default card persists without changing the active environment or opening a space")
    func persistsWithoutPresentationSideEffects() throws {
        let suite = "DefaultCardEnvironmentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = PlaybackPresentationModel(environmentDefaults: defaults)
        try model.activateEnvironment(.ocean, effect: .dark)
        let before = model.snapshot
        model.setDefaultCardEnvironment(.tidal)
        #expect(model.defaultCardEnvironment == .tidal)
        #expect(model.environmentContext == before.environmentContext)
        #expect(model.presentation == before.presentation)
        #expect(model.pendingSpatialPlatformEffect == nil)
        let reopened = PlaybackPresentationModel(environmentDefaults: defaults)
        #expect(reopened.defaultCardEnvironment == .tidal)
        try model.activateEnvironment(.ocean, effect: .light)
        #expect(model.defaultCardEnvironment == .tidal)
        #expect(PlaybackPresentationModel(environmentDefaults: defaults).defaultCardEnvironment == .tidal)
        let position = EnvironmentCarouselLayout.initialPosition(
            environments: FeaturedEnvironment.catalog,
            cardDefaultEnvironment: reopened.defaultCardEnvironment
        )
        let centered = EnvironmentCarouselLayout.renderSlots(
            environmentCount: FeaturedEnvironment.catalog.count,
            scrollPosition: position,
            maximumDistance: 2
        ).filter { $0.visualPosition == 0 }
        #expect(centered.map(\.environmentIndex) == [1])
    }

    @Test("unsupported saved card preferences use Ocean")
    func invalidSavedPreference() throws {
        let suite = "DefaultCardEnvironmentTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for value in ["removed-environment", "quiet-room"] {
            defaults.set(value, forKey: "defaultCardEnvironment")
            #expect(PlaybackPresentationModel(environmentDefaults: defaults).defaultCardEnvironment == .ocean)
        }
    }
}

@MainActor
struct PlaybackRefreshRateTests {
    @Test("video cadence chooses a supported integer-multiple preference")
    func frameRateMapping() {
        let cases: [(Double, Float)] = [
            (25.00073007621996, 100), (25.00083117228539, 100),
            (24, 96), (48, 96), (25, 100), (50, 100), (100, 100),
            (30, 90), (45, 90), (90, 90), (60, 120), (120, 120),
            (240, 120), (360, 120), (23.976, 96), (24000.0 / 1001, 96),
            (29.97, 90), (59.94, 120), (119.88, 120), (47.952, 96),
            (0, 90), (-1, 90), (.nan, 90), (.infinity, 90), (27, 90)
        ]
        for (frameRate, expected) in cases {
            #expect(PlaybackRefreshRatePolicy.requestedHz(for: frameRate) == expected)
        }
    }

    @Test("overlay separates requested rate from fractional display-link cadence")
    func overlayReportsIndependentRates() {
        let text = DeveloperStatsLine.text(
            metrics: .init(refreshHz: 95.904), sceneUpdatesPerSecond: 90,
            enqueuedSamplesPerSecond: nil, playback: nil, sessionIsActive: false,
            requestedRefreshHz: 96
        )
        #expect(text.contains("DisplayLink 95.904Hz"))
        #expect(text.contains("Requested 96Hz"))
        #expect(text.contains("Scene updates 90Hz"))
    }
}

#if os(visionOS) && !targetEnvironment(simulator)
@MainActor
struct PlaybackDisplayCriteriaLifecycleTests {
    @Test("display preference follows host handoff, opt-out, and playback exit")
    func requestsAndReleasesOnRealDisplayManagers() throws {
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264, width: 1920, height: 1080,
            extensions: nil, formatDescriptionOut: &description
        )
        #expect(status == noErr)
        let format = try #require(description)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let immersiveHost = UIWindow(windowScene: scene)
        let windowID = UUID()
        let immersiveID = UUID()
        let criteria = PlaybackDisplayCriteria()
        criteria.update(frameRate: 23.976, format: format)
        #expect(criteria.requestedHz == nil)
        #expect(criteria.statusText == "Waiting for window")
        criteria.setWindow(window, id: windowID, immersive: false)
        #expect(criteria.requestedHz == 96)
        #expect(window.avDisplayManager.preferredDisplayCriteria != nil)
        let submitted = window.avDisplayManager.preferredDisplayCriteria
        criteria.update(frameRate: 23.976, format: format)
        #expect(window.avDisplayManager.preferredDisplayCriteria === submitted)
        criteria.setWindow(immersiveHost, id: immersiveID, immersive: true)
        #expect(window.avDisplayManager.preferredDisplayCriteria === submitted)
        criteria.update(frameRate: 23.976, format: format, host: .immersiveSpace)
        #expect(criteria.requestedHz == 96)
        #expect(immersiveHost.avDisplayManager.preferredDisplayCriteria != nil)
        criteria.isEnabled = false
        #expect(criteria.statusText == "Off")
        #expect(criteria.requestedHz == nil)
        #expect(immersiveHost.avDisplayManager.preferredDisplayCriteria == nil)
        criteria.update(frameRate: 59.94, format: format, host: .immersiveSpace)
        criteria.isEnabled = true
        #expect(criteria.requestedHz == 120)
        #expect(immersiveHost.avDisplayManager.preferredDisplayCriteria != nil)
        criteria.update(frameRate: 59.94, format: format, host: .window)
        let windowRequest = window.avDisplayManager.preferredDisplayCriteria
        criteria.setWindow(nil, id: immersiveID, immersive: true)
        #expect(window.avDisplayManager.preferredDisplayCriteria === windowRequest)
        #expect(criteria.requestedHz == 120)
        #expect(window.avDisplayManager.preferredDisplayCriteria != nil)
        criteria.clear()
        #expect(criteria.statusText == "Not requested")
        #expect(criteria.requestedHz == nil)
        #expect(window.avDisplayManager.preferredDisplayCriteria == nil)
        #expect(immersiveHost.avDisplayManager.preferredDisplayCriteria == nil)
        criteria.isEnabled = false
        criteria.isEnabled = true
        #expect(criteria.requestedHz == nil)
    }
}
#endif
