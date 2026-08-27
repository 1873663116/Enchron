import Playback
import Testing
@testable import Enchron

@MainActor
struct EnvironmentSceneMappingTests {

    @Test("the catalog exposes the three Scenic environments and Skybox")
    func catalogUsesFourEnvironmentIdentities() {
        #expect(
            FeaturedEnvironment.catalog.map(\.environment)
                == [.scenicOne, .scenicTwo, .scenicThree, .skybox]
        )
        #expect(
            FeaturedEnvironment.catalog.map(\.id)
                == ["scenic-one", "scenic-two", "scenic-three", "skybox"]
        )
        #expect(
            SpatialSceneDomain.CinemaEnvironment.scenicEnvironments
                == [.scenicOne, .scenicTwo, .scenicThree]
        )
        #expect(SpatialSceneDomain.EnvironmentEffect.allCases == [.light, .dark])
    }

    @Test("all environment identities resolve through the shared world scene")
    func environmentsResolveToSharedWorldScene() {
        #expect(EnvironmentSceneMapping.worldSceneName == "Immersive")
        for environment in SpatialSceneDomain.CinemaEnvironment.allCases {
            #expect(
                EnvironmentSceneMapping.sceneName(forEnvironmentID: environment.rawValue)
                    == EnvironmentSceneMapping.worldSceneName
            )
        }
    }

    @Test("all environments currently share the placement recommendation")
    func defaultScreenScale() {
        for environment in SpatialSceneDomain.CinemaEnvironment.allCases {
            #expect(
                EnvironmentSceneMapping.defaultScreenScale(
                    forEnvironmentID: environment.rawValue
                ) == 1.3
            )
        }
    }

    @Test("persisted and invalid default values resolve safely")
    func defaultPreferenceMigration() {
        #expect(SpatialSceneDomain.CinemaEnvironment(preferenceValue: "enchron") == .scenicOne)
        #expect(SpatialSceneDomain.CinemaEnvironment(preferenceValue: "skybox") == nil)
        #expect(SpatialSceneDomain.CinemaEnvironment(preferenceValue: "scenic-three") == .scenicThree)
    }
}
