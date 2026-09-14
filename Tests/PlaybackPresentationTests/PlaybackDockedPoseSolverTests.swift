import EnvironmentSceneContract
import RealityKit
import Testing
@testable import Playback
import simd

@MainActor
@Suite("Playback docked pose solver")
struct PlaybackDockedPoseSolverTests {

    private static func restPose(
        bottomHeight: Float,
        distance: Float,
        screenHeight: Float,
        yawRadians: Float = 0,
        halfWidth: Float = 4
    ) -> EnvironmentScreenRestPose {
        let halfHeight = screenHeight / 2
        let rotation = simd_quatf(angle: yawRadians, axis: [0, 1, 0])
        return EnvironmentScreenRestPose(
            center: rotation.act(SIMD3<Float>(0, bottomHeight + halfHeight, -distance)),
            right: rotation.act(SIMD3<Float>(1, 0, 0)),
            up: [0, 1, 0],
            normal: rotation.act(SIMD3<Float>(0, 0, 1)),
            halfWidth: halfWidth,
            halfHeight: halfHeight
        )
    }

    @Test("zero elevation leaves the bottom edge at the authored rest height")
    func zeroElevationKeepsTheAuthoredBottomEdge() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let transform = PlaybackSurfaceTransform(
            distance: 10,
            elevationDegrees: 0,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            restPose: Self.restPose(bottomHeight: 0.75, distance: 15, screenHeight: 9),
            meshSize: .zero
        )

        #expect(abs(pose.bottomEdgeCenter.y - 0.75) < 0.0001)
        #expect(abs(pose.bottomEdgeCenter.z - -10) < 0.0001)
        #expect(abs(pose.center.y - 3) < 0.0001)
        #expect(abs(pose.center.z - -10) < 0.0001)
        #expect(abs(pose.center.x) < 0.0001)
        #expect(simd_length(pose.up - SIMD3<Float>(0, 1, 0)) < 0.0001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.0001)
        #expect(simd_length(pose.right - SIMD3<Float>(1, 0, 0)) < 0.0001)
        #expect(abs(pose.effectiveDistance - 10) < 0.0001)
        #expect(pose.roomPosition == .zero)
        #expect(abs(pose.roomRotation.real - 1) < 0.0001)
    }

    @Test("every screen height keeps the bottom edge on the authored rest height")
    func screenHeightGrowsUpwardFromTheBottomEdge() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let rest = Self.restPose(bottomHeight: 0.75, distance: 15, screenHeight: 9)

        for screenHeight in [4.5, 9.0, 12.0] {
            let pose = PlaybackDockedPoseSolver.solve(
                transform: PlaybackSurfaceTransform(
                    distance: 15,
                    elevationDegrees: 0,
                    scale: screenHeight
                ),
                geometry: geometry,
                restPose: rest,
                meshSize: .zero
            )

            #expect(abs(pose.bottomEdgeCenter.y - 0.75) < 0.0001)
            #expect(abs(pose.halfHeight - Float(screenHeight) / 2) < 0.0001)
            #expect(abs(pose.center.y - (0.75 + Float(screenHeight) / 2)) < 0.0001)
        }
    }

    @Test("elevation rotates the world rigidly without changing the requested distance")
    func elevationRotatesTheWorldWithoutChangingDistance() {
        let geometry = EnvironmentSceneMapping.geometry(for: .quietRoom)
        let transform = PlaybackSurfaceTransform(
            distance: 12,
            elevationDegrees: 90,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            restPose: Self.restPose(bottomHeight: 0.75, distance: 15.98, screenHeight: 4.5),
            meshSize: .zero
        )

        #expect(abs(pose.effectiveDistance - 12) < 0.0001)
        #expect(simd_length(pose.bottomEdgeCenter - SIMD3<Float>(0, 12.75, 0)) < 0.001)
        #expect(simd_length(pose.up - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, -1, 0)) < 0.001)
        let rotated = pose.roomRotation.act(SIMD3<Float>(0, 1, 0))
        #expect(simd_length(rotated - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(simd_length(pose.roomPosition - SIMD3<Float>(0, -3.23, -0.75)) < 0.01)
    }

    @Test("a viewer-moving environment carries the screen with the room")
    func movesViewerCarriesTheScreenWithTheRoom() {
        let geometry = EnvironmentSceneMapping.geometry(for: .quietRoom)
        let transform = PlaybackSurfaceTransform(
            distance: 8,
            elevationDegrees: 0,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            restPose: Self.restPose(bottomHeight: 0.75, distance: 15.98, screenHeight: 4.5),
            meshSize: .zero
        )

        #expect(abs(pose.effectiveDistance - 8) < 0.0001)
        #expect(abs(pose.center.z - -8) < 0.0001)
        #expect(abs(pose.roomPosition.z - (15.98 - 8)) < 0.0001)
        #expect(abs((pose.center.z - pose.roomPosition.z) - -15.98) < 0.0001)
        #expect(abs(pose.roomPosition.x) < 0.0001)
        #expect(abs(pose.roomPosition.y) < 0.0001)
    }

    @Test("viewer height lowers the room and the screen together")
    func viewerHeightMovesTheWorldVertically() {
        let geometry = EnvironmentSceneMapping.geometry(for: .quietRoom)
        let rest = Self.restPose(bottomHeight: 0.75, distance: 15.98, screenHeight: 4.5)
        let level = PlaybackDockedPoseSolver.solve(
            transform: PlaybackSurfaceTransform(distance: 10, elevationDegrees: 0, scale: 4.5),
            geometry: geometry,
            restPose: rest,
            meshSize: .zero
        )
        let raised = PlaybackDockedPoseSolver.solve(
            transform: PlaybackSurfaceTransform(distance: 10, elevationDegrees: 0, scale: 4.5, viewerHeight: 1.5),
            geometry: geometry,
            restPose: rest,
            meshSize: .zero
        )

        #expect(abs(raised.center.y - (level.center.y - 1.5)) < 0.0001)
        #expect(abs(raised.roomPosition.y - (level.roomPosition.y - 1.5)) < 0.0001)
        #expect(abs(raised.center.z - level.center.z) < 0.0001)
        #expect(abs(raised.roomPosition.z - level.roomPosition.z) < 0.0001)
    }

    @Test("elevation pitches a screen-moving environment's room around the bottom-edge pivot")
    func elevationPitchesTheMovesScreenRoom() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let transform = PlaybackSurfaceTransform(
            distance: 8,
            elevationDegrees: 30,
            scale: 9
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            restPose: Self.restPose(bottomHeight: 0.75, distance: 15, screenHeight: 9),
            meshSize: .zero
        )

        let pivot = SIMD3<Float>(0, 0.75, 0)
        let rotated = pose.roomRotation.act(-pivot) + pivot
        #expect(simd_length(pose.roomPosition - rotated) < 0.001)
        #expect(abs(pose.roomPosition.y - (0.75 - 0.75 * cos(.pi / 6))) < 0.001)
        #expect(abs(pose.roomPosition.z - (-0.375)) < 0.001)
        #expect(abs(pose.effectiveDistance - 8) < 0.0001)
    }

    @Test("the authored yaw rotates the whole basis and the bottom edge around the wearer")
    func authoredYawRotatesTheBasis() {
        let geometry = EnvironmentSceneMapping.geometry(for: .ocean)
        let transform = PlaybackSurfaceTransform(
            distance: 10,
            elevationDegrees: 0,
            scale: 4.5
        )

        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            restPose: Self.restPose(
                bottomHeight: 0.75,
                distance: 15,
                screenHeight: 9,
                yawRadians: .pi / 2
            ),
            meshSize: .zero
        )

        #expect(simd_length(pose.center - SIMD3<Float>(-10, 3, 0)) < 0.001)
        #expect(simd_length(pose.right - SIMD3<Float>(0, 0, -1)) < 0.001)
        #expect(simd_length(pose.up - SIMD3<Float>(0, 1, 0)) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(1, 0, 0)) < 0.001)
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
            restPose: Self.restPose(bottomHeight: 0.75, distance: 15, screenHeight: 9),
            meshSize: meshSize
        )

        #expect(abs(pose.meshScale - (3.6 / 2)) < 0.0001)
        #expect(abs(pose.halfHeight - 1.8) < 0.0001)
        #expect(abs(pose.halfWidth - 3.6) < 0.0001)
    }
}

@MainActor
@Suite("Environment screen rest pose")
struct EnvironmentScreenRestPoseTests {

    @Test("the Quiet Room docking region yields a 14.23 by 8 metre wall screen")
    func quietRoomDockingRegionYieldsTheAuthoredWallScreen() {
        let region = Transform(
            scale: .one,
            rotation: simd_quatf(angle: 0, axis: [0, 1, 0]),
            translation: [0, 3.5, -7.98]
        )

        let pose = EnvironmentScreenRestPose(
            dockingRegionWorldTransform: region.matrix,
            width: 14.23,
            screenHeight: 8
        )

        #expect(abs(pose.screenWidth - 14.23) < 0.001)
        #expect(abs(pose.screenHeight - 8) < 0.001)
        #expect(abs(pose.bottomHeight - -0.5) < 0.001)
        #expect(abs(pose.distance - 7.98) < 0.001)
        #expect(abs(pose.yawRadians) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(simd_length(pose.up - SIMD3<Float>(0, 1, 0)) < 0.001)
        #expect(simd_length(pose.right - SIMD3<Float>(1, 0, 0)) < 0.001)
    }

    @Test("the Ocean docking region is read through the yawed and offset scene root")
    func oceanDockingRegionIsReadThroughTheSceneRoot() {
        let root = Transform(
            scale: .one,
            rotation: simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]),
            translation: [0, -5, 0]
        )
        let region = Transform(
            scale: .one,
            rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]),
            translation: [-15, 5.2, 0]
        )

        let pose = EnvironmentScreenRestPose(
            dockingRegionWorldTransform: root.matrix * region.matrix,
            width: 14.23,
            screenHeight: 8
        )

        #expect(simd_length(pose.center - SIMD3<Float>(0, 0.2, -15)) < 0.001)
        #expect(abs(pose.screenWidth - 14.23) < 0.001)
        #expect(abs(pose.screenHeight - 8) < 0.001)
        #expect(abs(pose.distance - 15) < 0.001)
        #expect(abs(pose.bottomHeight - -3.8) < 0.001)
        #expect(abs(pose.yawRadians) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.001)
    }

    @Test("a docking region facing away from the wearer is turned around")
    func dockingRegionFacingAwayIsTurnedAround() {
        let region = Transform(
            scale: .one,
            rotation: simd_quatf(angle: .pi, axis: [0, 1, 0]),
            translation: [0, 3.5, -7.98]
        )

        let pose = EnvironmentScreenRestPose(
            dockingRegionWorldTransform: region.matrix,
            width: 14.23,
            screenHeight: 8
        )

        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(simd_length(pose.right - SIMD3<Float>(1, 0, 0)) < 0.001)
        #expect(abs(pose.screenHeight - 8) < 0.001)
        #expect(abs(pose.screenWidth - 14.23) < 0.001)
    }
}
