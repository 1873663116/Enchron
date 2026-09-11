import EnvironmentSceneContract
import Testing
@testable import Playback
import simd

@MainActor
@Suite("Playback docked pose solver")
struct PlaybackDockedPoseSolverTests {

    @Test("zero elevation places the center directly in front of the viewer at rest height")
    func zeroElevationPlacesCenterInFrontOfViewer() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let transform = PlaybackSurfaceTransform(
            distance: 10,
            elevationDegrees: 0,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            anchorWorldPosition: [0, 0, -10],
            meshSize: .zero
        )

        #expect(abs(pose.center.x - 0) < 0.0001)
        #expect(abs(pose.center.y - 3) < 0.0001)
        #expect(abs(pose.center.z - -10) < 0.0001)
        #expect(pose.ceilingClamped == false)
        #expect(abs(pose.effectiveDistance - 10) < 0.0001)
    }

    @Test("a 6 meter ceiling clamps a 4.5 meter screen at 90 degrees to ceiling minus clearance")
    func ceilingClampsHighElevationScreenToCeilingMinusClearance() {
        let geometry = EnvironmentSceneMapping.geometry(for: .quietRoom)
        let transform = PlaybackSurfaceTransform(
            distance: 12,
            elevationDegrees: 90,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            anchorWorldPosition: [0, 0, -12],
            meshSize: .zero
        )

        #expect(pose.ceilingClamped == true)
        #expect(abs(pose.center.y - (6.0 - 0.05)) < 0.001)
    }

    @Test("a viewer-moving environment offsets the room by the anchor depth and requested distance")
    func movesViewerYieldsRoomOffsetFromAnchorAndDistance() {
        let geometry = EnvironmentSceneMapping.geometry(for: .quietRoom)
        let transform = PlaybackSurfaceTransform(
            distance: 8,
            elevationDegrees: 0,
            scale: 4.5
        )
        let anchor: SIMD3<Float> = [1, 2, -5]

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            anchorWorldPosition: anchor,
            meshSize: .zero
        )

        #expect(abs(pose.roomOffsetZ - (-anchor.z - 8)) < 0.0001)
    }

    @Test("a screen-moving environment never offsets the room")
    func movesScreenYieldsNoRoomOffset() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let transform = PlaybackSurfaceTransform(
            distance: 8,
            elevationDegrees: 30,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            anchorWorldPosition: [1, 2, -5],
            meshSize: .zero
        )

        #expect(pose.roomOffsetZ == 0)
    }

    @Test("mesh scale carries the screen height into the authored mesh's own height units")
    func meshScaleDividesScreenHeightByMeshHeight() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let transform = PlaybackSurfaceTransform(
            distance: 10,
            elevationDegrees: 0,
            scale: 3.6
        )
        let meshSize: SIMD2<Float> = [4, 2]

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            anchorWorldPosition: [0, 0, -10],
            meshSize: meshSize
        )

        #expect(abs(pose.meshScale - (3.6 / 2)) < 0.0001)
        #expect(abs(pose.halfHeight - 1.8) < 0.0001)
        #expect(abs(pose.halfWidth - 3.6) < 0.0001)
    }
}
