import Testing
@testable import XrPlayerCore

/// Verifies the card → scene mapping for the immersive entry path (ENV-18 prereq):
/// every featured-environment card resolves to the single `world` scene, and the
/// mapping is total (never nil).
struct EnvironmentSceneMappingTests {

    @Test("every featured environment card maps to the world scene")
    func allCardsMapToWorld() {
        let cardIDs = [
            "snow-village", "dune-observatory", "neon-canopy", "forest-shrine",
            "ocean-temple", "orbital-garden", "dream-cinema"
        ]
        for id in cardIDs {
            #expect(EnvironmentSceneMapping.sceneName(forEnvironmentID: id) == "world")
        }
    }

    @Test("an unknown card id still resolves to a non-empty scene name")
    func unknownIDStillResolves() {
        let name = EnvironmentSceneMapping.sceneName(forEnvironmentID: "does-not-exist")
        #expect(name == EnvironmentSceneMapping.worldSceneName)
        #expect(!name.isEmpty)
    }
}
