import RealityKit
import SwiftUI
import simd

struct LazyGazeFollow: Equatable {
    struct Gaze: Equatable {
        var yaw: Float
        var pitch: Float
    }

    static let deadZoneRadians: Float = 8 * .pi / 180
    static let settleRadians: Float = 0.75 * .pi / 180
    static let timeConstantSeconds: Float = 0.4
    static let dockCaptureRadians: Float = 15 * .pi / 180
    static let dockReleaseRadians: Float = 25 * .pi / 180

    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    private(set) var isChasing = false
    private(set) var isDocked = false
    private var hasTarget = false

    static func gaze(of forward: SIMD3<Float>) -> (yaw: Float, pitch: Float) {
        let length = simd_length(forward)
        guard length > 0 else { return (0, 0) }
        let unit = forward / length
        return (
            yaw: atan2(-unit.x, -unit.z),
            pitch: asin(min(max(unit.y, -1), 1))
        )
    }

    mutating func advance(
        towardYaw targetYaw: Float,
        pitch targetPitch: Float,
        deltaTime: Float
    ) {
        advance(
            head: Gaze(yaw: targetYaw, pitch: targetPitch),
            dock: nil,
            deltaTime: deltaTime
        )
    }

    mutating func advance(head: Gaze, dock: Gaze?, deltaTime: Float) {
        guard hasTarget else {
            hasTarget = true
            yaw = head.yaw
            pitch = head.pitch
            return
        }
        if let dock {
            let headToDock = abs(Self.wrapped(dock.yaw - head.yaw))
            if isDocked {
                isDocked = headToDock < Self.dockReleaseRadians
            } else {
                isDocked = headToDock < Self.dockCaptureRadians
            }
        } else {
            isDocked = false
        }
        let target = isDocked ? dock ?? head : head
        let yawDelta = Self.wrapped(target.yaw - yaw)
        let pitchDelta = target.pitch - pitch
        let distance = (yawDelta * yawDelta + pitchDelta * pitchDelta).squareRoot()
        if isChasing == false {
            guard isDocked || distance > Self.deadZoneRadians else { return }
            isChasing = true
        }
        if distance < Self.settleRadians {
            isChasing = false
            return
        }
        let factor = 1 - exp(-max(deltaTime, 0) / Self.timeConstantSeconds)
        yaw = Self.wrapped(yaw + yawDelta * factor)
        pitch += pitchDelta * factor
    }

    static func distance(from lhs: Gaze, to rhs: Gaze) -> Float {
        let yawDelta = wrapped(rhs.yaw - lhs.yaw)
        let pitchDelta = rhs.pitch - lhs.pitch
        return (yawDelta * yawDelta + pitchDelta * pitchDelta).squareRoot()
    }

    var orientation: simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    private static func wrapped(_ angle: Float) -> Float {
        var value = angle
        while value > .pi { value -= 2 * .pi }
        while value < -.pi { value += 2 * .pi }
        return value
    }
}

@MainActor
final class PanoramaSubtitleFollower {
    let root: Entity = {
        let entity = Entity()
        entity.name = "EnchronSubtitle.follower"
        return entity
    }()

    static let dockedScale: Float =
        -ImmersivePlaybackControlsAttachmentController.forwardOffsetMeters
        / PlaybackSubtitlePlacement.panoramaScreenDistance

    static let dockedSubtitleBottomAboveControlsMeters: Float = 0.10
    static let dockTransitionSpeedMetersPerSecond: Float = 6.3
    static let minimumDockTransitionSeconds: Float = 0.12
    static let dockArcHeightMeters: Float = 0.35

    var dockTransformProvider: @MainActor () -> Transform? = { nil }

    private var wasDocked = false
    private var transitionTimeConstant: Float = LazyGazeFollow.timeConstantSeconds
    private var transitionTravel: Float = 0
    private var arcLift: Float = 0

    private var follow = LazyGazeFollow()
    private var headPoseSource: HeadPoseSource?
    private var updateSubscription: EventSubscription?

    func setActive(
        _ active: Bool,
        in content: RealityViewContent,
        headPoseSource: HeadPoseSource
    ) {
        let installed = content.entities.contains { $0 === root }
        if active {
            if installed == false {
                content.add(root)
            }
            if self.headPoseSource !== headPoseSource {
                self.headPoseSource?.release(self)
                self.headPoseSource = headPoseSource
            }
            headPoseSource.retain(self)
            if updateSubscription == nil {
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                    self?.step(deltaTime: Float(event.deltaTime))
                }
            }
        } else {
            stop()
            if installed {
                content.remove(root)
            }
        }
    }

    func stop() {
        updateSubscription?.cancel()
        updateSubscription = nil
        headPoseSource?.release(self)
        headPoseSource = nil
        follow = LazyGazeFollow()
        wasDocked = false
        transitionTimeConstant = LazyGazeFollow.timeConstantSeconds
        transitionTravel = 0
        arcLift = 0
        root.scale = .one
        root.removeFromParent()
    }

    static func dockedRootTransform(controls: Transform) -> Transform {
        let scale = dockedScale
        let screenCenter = PlaybackSubtitlePlacement.panoramaScreenCenter
        let screenSize = PlaybackSubtitlePlacement.panoramaScreenSize
        let subtitleBottomBelowScreenCenter =
            screenSize.y / 2 - screenSize.y * PlaybackSubtitlePlacement.pinnedBottomFraction
        let screenCenterAboveControls =
            dockedSubtitleBottomAboveControlsMeters + subtitleBottomBelowScreenCenter * scale
        let screenCenterWorld = controls.translation
            + controls.rotation.act([0, screenCenterAboveControls, 0])
        return Transform(
            scale: SIMD3(repeating: scale),
            rotation: controls.rotation,
            translation: screenCenterWorld - controls.rotation.act(screenCenter * scale)
        )
    }

    static func screenCenterWorld(of root: Transform) -> SIMD3<Float> {
        root.translation
            + root.rotation.act(PlaybackSubtitlePlacement.panoramaScreenCenter * root.scale)
    }

    private func step(deltaTime: Float) {
        guard let headPoseSource,
              case let .pose(transform) = headPoseSource.pose() else {
            return
        }
        let forward = -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let headPosition = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let headGaze = LazyGazeFollow.gaze(of: forward)
        let dockTransform = dockTransformProvider()
        let dockGaze = dockTransform.map { dock in
            LazyGazeFollow.gaze(of: dock.translation - headPosition)
        }
        follow.advance(
            head: LazyGazeFollow.Gaze(yaw: headGaze.yaw, pitch: headGaze.pitch),
            dock: dockGaze.map { LazyGazeFollow.Gaze(yaw: $0.yaw, pitch: headGaze.pitch) },
            deltaTime: deltaTime
        )
        let target: Transform
        if follow.isDocked, let dockTransform {
            target = Self.dockedRootTransform(controls: dockTransform)
        } else {
            target = Transform(
                scale: .one,
                rotation: follow.orientation,
                translation: headPosition
            )
        }
        let unliftedRoot = Transform(
            scale: root.scale,
            rotation: root.orientation,
            translation: root.position - [0, arcLift, 0]
        )
        if follow.isDocked != wasDocked {
            wasDocked = follow.isDocked
            transitionTravel = simd_distance(
                Self.screenCenterWorld(of: unliftedRoot),
                Self.screenCenterWorld(of: target)
            )
            transitionTimeConstant = max(
                transitionTravel / Self.dockTransitionSpeedMetersPerSecond,
                Self.minimumDockTransitionSeconds
            )
        }
        let factor = 1 - exp(-max(deltaTime, 0) / transitionTimeConstant)
        let eased = Transform(
            scale: simd_mix(unliftedRoot.scale, target.scale, SIMD3(repeating: factor)),
            rotation: simd_slerp(unliftedRoot.rotation, target.rotation, factor),
            translation: simd_mix(unliftedRoot.translation, target.translation, SIMD3(repeating: factor))
        )
        let remaining = simd_distance(
            Self.screenCenterWorld(of: eased),
            Self.screenCenterWorld(of: target)
        )
        let progress = transitionTravel > 0 ? 1 - min(remaining / transitionTravel, 1) : 1
        arcLift = Self.dockArcHeightMeters * sin(progress * .pi)
        root.transform = Transform(
            scale: eased.scale,
            rotation: eased.rotation,
            translation: eased.translation + [0, arcLift, 0]
        )
    }
}
