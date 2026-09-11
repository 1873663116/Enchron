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
        #expect(ocean.distanceRangeMeters == 6...30)
        #expect(ocean.defaultDistanceMeters == 12)
        #expect(ocean.elevationRangeDegrees == 0...90)
        #expect(ocean.screenHeightRangeMeters == 2...6)
        #expect(ocean.defaultScreenHeightMeters == 4.5)

        for placeholder: SpatialSceneDomain.CinemaEnvironment in [
            .placeholderRed, .placeholderGreen, .placeholderBlue
        ] {
            let geometry = EnvironmentSceneMapping.geometry(for: placeholder)
            #expect(geometry.distanceRangeMeters == 6...30)
            #expect(geometry.defaultDistanceMeters == 12)
            #expect(geometry.elevationRangeDegrees == 0...90)
            #expect(geometry.screenHeightRangeMeters == 2...6)
            #expect(geometry.defaultScreenHeightMeters == 4.5)
        }

        let quietRoom = EnvironmentSceneMapping.geometry(for: .quietRoom)
        #expect(quietRoom.distanceRangeMeters == 6...15.5)
        #expect(quietRoom.defaultDistanceMeters == 12)
        #expect(quietRoom.elevationRangeDegrees == 0...90)
        #expect(quietRoom.screenHeightRangeMeters == 2...5.5)
        #expect(quietRoom.defaultScreenHeightMeters == 4.5)

        #expect(EnvironmentSceneMapping.descriptor(for: .quietRoom).supportsDarkAppearance == false)
        #expect(EnvironmentSceneMapping.descriptor(for: .ocean).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .placeholderRed).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .placeholderGreen).supportsDarkAppearance == true)
        #expect(EnvironmentSceneMapping.descriptor(for: .placeholderBlue).supportsDarkAppearance == true)
    }

    @Test("every environment identity, valid or not, defaults its screen height to 4.5 meters")
    func defaultScreenHeightMetersIsAlwaysFourAndAHalf() {
        for environment in SpatialSceneDomain.CinemaEnvironment.allCases {
            #expect(
                EnvironmentSceneMapping.defaultScreenHeightMeters(
                    forEnvironmentID: environment.rawValue
                ) == 4.5
            )
        }
        #expect(
            EnvironmentSceneMapping.defaultScreenHeightMeters(forEnvironmentID: "not-a-real-environment")
                == 4.5
        )
    }
}
