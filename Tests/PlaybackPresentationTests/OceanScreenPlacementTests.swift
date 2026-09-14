import EnvironmentSceneContract
import Playback
import Testing
import simd

@MainActor
struct OceanScreenPlacementTests {
    @Test("the loaded ocean screen grows upward and preserves the scene and viewing distances")
    func loadedOceanScreenPreservesBottomEdge() async throws {
        let scene = try #require(EnvironmentSceneMapping.scene(for: .ocean))
        let root = try await scene.load()
        let authored = try #require(
            EnvironmentScreenRestPose.dockingRegion(in: root, screenHeight: 16)
        )
        let rest = try #require(scene.restPose)
        #expect(abs(rest.screenHeight - 20) < 0.001)
        #expect(abs(rest.center.y - authored.center.y - 2) < 0.001)
        #expect(abs(rest.bottomHeight - authored.bottomHeight) < 0.001)
        #expect(abs(rest.distance - authored.distance) < 0.001)

        let geometry = scene.descriptor.geometry
        for distance in [12.0, 13.0, 47.0] {
            for elevation in [0.0, 30.0, 90.0] {
                for viewerHeight in [-3.0, -2.0, 5.0] {
                    let original = PlaybackDockedPoseSolver.solve(
                        transform: PlaybackSurfaceTransform(
                            distance: distance, elevationDegrees: elevation,
                            scale: 16, viewerHeight: viewerHeight
                        ),
                        geometry: geometry, restPose: authored, meshSize: [16, 9]
                    )
                    let enlarged = PlaybackDockedPoseSolver.solve(
                        transform: PlaybackSurfaceTransform(
                            distance: distance, elevationDegrees: elevation,
                            scale: 20, viewerHeight: viewerHeight
                        ),
                        geometry: geometry, restPose: rest, meshSize: [16, 9]
                    )
                    #expect(simd_distance(enlarged.bottomEdgeCenter, original.bottomEdgeCenter) < 0.001)
                    #expect(simd_distance(enlarged.roomPosition, original.roomPosition) < 0.001)
                    #expect(abs(enlarged.effectiveDistance - Float(distance)) < 0.001)
                    #expect(abs(enlarged.halfHeight - 10) < 0.001)
                    #expect(abs(enlarged.halfWidth * 2 - 35.555556) < 0.001)
                }
            }
        }
    }
}
