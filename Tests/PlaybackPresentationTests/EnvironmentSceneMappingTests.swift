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

    @Test("the catalog exposes Ocean followed by the three placeholders, in that order")
    func catalogUsesOceanAndThreePlaceholders() {
        #expect(
            FeaturedEnvironment.catalog.map(\.environment)
                == [.ocean, .placeholderRed, .placeholderGreen, .placeholderBlue]
        )
        #expect(
            FeaturedEnvironment.catalog.map(\.id)
                == ["ocean", "placeholder-red", "placeholder-green", "placeholder-blue"]
        )
        #expect(
            SpatialSceneDomain.CinemaEnvironment.cardEnvironments
                == [.ocean, .placeholderRed, .placeholderGreen, .placeholderBlue]
        )
        #expect(SpatialSceneDomain.EnvironmentEffect.allCases == [.light, .dark])
    }

    @Test("Quiet Room is the only default environment and the only one without dark appearance")
    func quietRoomIsTheUnconfigurableDefault() {
        #expect(SpatialSceneDomain.CinemaEnvironment.defaultEnvironment == .quietRoom)
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
        #expect(ocean.defaultDistanceMeters == 20)
        #expect(ocean.viewerHeightRangeMeters == -3...5)
        #expect(ocean.defaultViewerHeightMeters == 0)
        #expect(ocean.elevationRangeDegrees == 0...90)
        #expect(ocean.screenHeightRangeMeters == 20...20)
        #expect(ocean.defaultScreenHeightMeters == 20)
        #expect(ocean.distanceStrategy == .movesViewer)
        #expect(ocean.ceilingHeightMeters == nil)

        for placeholder: SpatialSceneDomain.CinemaEnvironment in [
            .placeholderRed, .placeholderGreen, .placeholderBlue
        ] {
            let geometry = EnvironmentSceneMapping.geometry(for: placeholder)
            #expect(geometry.distanceRangeMeters == 6...30)
            #expect(geometry.defaultDistanceMeters == 12)
            #expect(geometry.elevationRangeDegrees == 0...90)
            #expect(geometry.screenHeightRangeMeters == 8...8)
            #expect(geometry.defaultScreenHeightMeters == 8)
        }

        let quietRoom = EnvironmentSceneMapping.geometry(for: .quietRoom)
        #expect(quietRoom.distanceRangeMeters == 5...18)
        #expect(quietRoom.defaultDistanceMeters == 8)
        #expect(quietRoom.defaultViewerHeightMeters == 1.5)
        #expect(quietRoom.viewerHeightRangeMeters == -1...3)
        #expect(quietRoom.elevationRangeDegrees == 0...90)
        #expect(quietRoom.screenHeightRangeMeters == 8...8)
        #expect(quietRoom.defaultScreenHeightMeters == 8)
        #expect(quietRoom.distanceStrategy == .movesViewer)
        #expect(quietRoom.ceilingHeightMeters == 7.75)

        #expect(EnvironmentSceneMapping.descriptor(for: .quietRoom).supportsDarkAppearance == false)
        #expect(EnvironmentSceneMapping.descriptor(for: .ocean).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .placeholderRed).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .placeholderGreen).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .placeholderBlue).supportsDarkAppearance == true)
    }

    @Test("environment IDs resolve their screen heights with the placeholder fallback")
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
        model.setDefaultCardEnvironment(.placeholderGreen)
        #expect(model.defaultCardEnvironment == .placeholderGreen)
        #expect(model.environmentContext == before.environmentContext)
        #expect(model.presentation == before.presentation)
        #expect(model.pendingSpatialPlatformEffect == nil)
        let reopened = PlaybackPresentationModel(environmentDefaults: defaults)
        #expect(reopened.defaultCardEnvironment == .placeholderGreen)
        try model.activateEnvironment(.placeholderBlue, effect: .light)
        #expect(model.defaultCardEnvironment == .placeholderGreen)
        #expect(PlaybackPresentationModel(environmentDefaults: defaults).defaultCardEnvironment == .placeholderGreen)
        let position = EnvironmentCarouselLayout.initialPosition(
            environments: FeaturedEnvironment.catalog,
            defaultEnvironment: reopened.defaultCardEnvironment
        )
        let centered = EnvironmentCarouselLayout.renderSlots(
            environmentCount: FeaturedEnvironment.catalog.count,
            scrollPosition: position,
            maximumDistance: 2
        ).filter { $0.visualPosition == 0 }
        #expect(centered.map(\.environmentIndex) == [2])
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

#if os(visionOS)
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
