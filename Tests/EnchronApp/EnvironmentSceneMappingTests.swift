import PlaybackPresentation
import Testing
@testable import Enchron

/// Verifies that Day and Night are effects of one Environment identity.
struct EnvironmentSceneMappingTests {

    @Test("the catalog exposes one card per environment identity")
    func catalogUsesOneEnvironmentIdentity() {
        #expect(FeaturedEnvironment.catalog.map(\.environment) == [.enchron])
        #expect(FeaturedEnvironment.catalog.map(\.id) == ["enchron"])
        #expect(SpatialSceneDomain.EnvironmentEffect.allCases == [.day, .night])
    }

    @Test("the environment identity resolves to the current placeholder scene")
    func environmentResolvesToPlaceholderScene() {
        let name = EnvironmentSceneMapping.sceneName(forEnvironmentID: SpatialSceneDomain.CinemaEnvironment.enchron.rawValue)
        #expect(name == EnvironmentSceneMapping.worldSceneName)
        #expect(!name.isEmpty)
    }

    @Test("Day and Night share the environment placement recommendation")
    func defaultScreenScale() {
        let environmentID = SpatialSceneDomain.CinemaEnvironment.enchron.rawValue
        #expect(EnvironmentSceneMapping.defaultScreenScale(forEnvironmentID: environmentID) == 1.3)
    }
}
