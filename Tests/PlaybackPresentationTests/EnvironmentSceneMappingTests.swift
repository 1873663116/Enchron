import EnvironmentSceneContract
import Playback
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
        #expect(ocean.defaultDistanceMeters == 13)
        #expect(ocean.viewerHeightRangeMeters == -3...5)
        #expect(ocean.defaultViewerHeightMeters == -2)
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
        #expect(quietRoom.defaultDistanceMeters == 7.98)
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
