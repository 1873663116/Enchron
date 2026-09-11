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
        #expect(pose.ceilingClamped == false)
        #expect(abs(pose.effectiveDistance - 10) < 0.0001)
        #expect(pose.roomOffset == .zero)
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

    @Test("a ceiling clamps the distance so the flat screen's top edge stops below it")
    func ceilingClampsTheTopEdgeOfTheFlatScreen() {
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

        let topEdge = pose.bottomEdgeCenter + 2 * pose.halfHeight * pose.up
        #expect(pose.ceilingClamped == true)
        #expect(abs(topEdge.y - (6.0 - 0.05)) < 0.001)
        #expect(abs(pose.bottomEdgeCenter.y - (6.0 - 0.05)) < 0.001)
        #expect(abs(pose.effectiveDistance - 5.2) < 0.001)
        #expect(simd_length(pose.up - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, -1, 0)) < 0.001)
    }

    @Test("a viewer-moving environment holds the rest distance and offsets the room instead")
    func movesViewerHoldsTheRestDistanceAndOffsetsTheRoom() {
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

        #expect(abs(pose.effectiveDistance - 15.98) < 0.0001)
        #expect(abs(pose.center.z - -15.98) < 0.0001)
        #expect(abs(pose.roomOffset.z - (15.98 - 8)) < 0.0001)
        #expect(abs(pose.roomOffset.x) < 0.0001)
        #expect(abs(pose.roomOffset.y) < 0.0001)
    }

    @Test("a screen-moving environment never offsets the room")
    func movesScreenYieldsNoRoomOffset() {
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

        #expect(pose.roomOffset == .zero)
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

    @Test("the Quiet Room ScreenPreview plane yields an 8 by 4.5 metre wall screen")
    func quietRoomPreviewYieldsTheAuthoredWallScreen() {
        let preview = Transform(
            scale: [8, 1, 4.5],
            rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]),
            translation: [0, 3, -15.98]
        )

        let pose = EnvironmentScreenRestPose(screenPreviewWorldTransform: preview.matrix)

        #expect(abs(pose.screenWidth - 8) < 0.001)
        #expect(abs(pose.screenHeight - 4.5) < 0.001)
        #expect(abs(pose.bottomHeight - 0.75) < 0.001)
        #expect(abs(pose.distance - 15.98) < 0.001)
        #expect(abs(pose.yawRadians) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(simd_length(pose.up - SIMD3<Float>(0, 1, 0)) < 0.001)
        #expect(simd_length(pose.right - SIMD3<Float>(1, 0, 0)) < 0.001)
    }

    @Test("the Ocean ScreenPreview plane is read through the yawed and offset scene root")
    func oceanPreviewIsReadThroughTheSceneRoot() {
        let root = Transform(
            scale: .one,
            rotation: simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]),
            translation: [0, -5, 0]
        )
        let preview = Transform(
            scale: [9, 1, 16],
            rotation: simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]),
            translation: [-15, 5.2, 0]
        )

        let pose = EnvironmentScreenRestPose(
            screenPreviewWorldTransform: root.matrix * preview.matrix
        )

        #expect(simd_length(pose.center - SIMD3<Float>(0, 0.2, -15)) < 0.001)
        #expect(abs(pose.screenWidth - 16) < 0.001)
        #expect(abs(pose.screenHeight - 9) < 0.001)
        #expect(abs(pose.distance - 15) < 0.001)
        #expect(abs(pose.bottomHeight - -4.3) < 0.001)
        #expect(abs(pose.yawRadians) < 0.001)
        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.001)
    }

    @Test("a preview facing away from the wearer is turned around")
    func previewFacingAwayIsTurnedAround() {
        let preview = Transform(
            scale: [8, 1, 4.5],
            rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]),
            translation: [0, 3, -15.98]
        )

        let pose = EnvironmentScreenRestPose(screenPreviewWorldTransform: preview.matrix)

        #expect(simd_length(pose.normal - SIMD3<Float>(0, 0, 1)) < 0.001)
        #expect(abs(pose.screenHeight - 4.5) < 0.001)
        #expect(abs(pose.screenWidth - 8) < 0.001)
    }
}
