import ARKit
import QuartzCore
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
    static let dockTransitionSeconds: Float = 0.45

    var dockTransformProvider: @MainActor () -> Transform? = { nil }

    private var wasDocked = false
    private var transitionStart: Transform?
    private var transitionElapsed: Float = 0

    private var follow = LazyGazeFollow()
    private var session: ARKitSession?
    private var provider: WorldTrackingProvider?
    private var trackingIsRunning = false
    private var generation = UUID()
    private var updateSubscription: EventSubscription?

    func setActive(_ active: Bool, in content: RealityViewContent) {
        let installed = content.entities.contains { $0 === root }
        if active {
            if installed == false {
                content.add(root)
            }
            startTrackingIfNeeded()
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
        session?.stop()
        session = nil
        provider = nil
        trackingIsRunning = false
        generation = UUID()
        follow = LazyGazeFollow()
        wasDocked = false
        transitionStart = nil
        transitionElapsed = 0
        root.scale = .one
        root.removeFromParent()
    }

    private func startTrackingIfNeeded() {
        guard session == nil, WorldTrackingProvider.isSupported else { return }
        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        let generation = UUID()
        self.session = session
        self.provider = provider
        self.generation = generation
        Task { @MainActor [weak self] in
            do {
                try await session.run([provider])
                guard let self, self.generation == generation else { return }
                self.trackingIsRunning = true
            } catch {
                guard let self, self.generation == generation else { return }
                session.stop()
                self.session = nil
                self.provider = nil
                self.trackingIsRunning = false
            }
        }
    }

    // The subtitle keeps its free-floating local layout while docked; the root
    // is placed so that layout lands on the controls' plane with the pinned
    // subtitle bottom a fixed distance above the controls' centre.
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

    private func step(deltaTime: Float) {
        guard trackingIsRunning,
              let provider,
              let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked else {
            return
        }
        let transform = anchor.originFromAnchorTransform
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
        if follow.isDocked != wasDocked {
            wasDocked = follow.isDocked
            transitionStart = root.transform
            transitionElapsed = 0
        }
        guard let start = transitionStart else {
            root.transform = target
            return
        }
        transitionElapsed += max(deltaTime, 0)
        let progress = min(transitionElapsed / Self.dockTransitionSeconds, 1)
        let eased = progress * progress * (3 - 2 * progress)
        root.transform = Transform(
            scale: simd_mix(start.scale, target.scale, SIMD3(repeating: eased)),
            rotation: simd_slerp(start.rotation, target.rotation, eased),
            translation: simd_mix(start.translation, target.translation, SIMD3(repeating: eased))
        )
        if progress >= 1 {
            transitionStart = nil
        }
    }
}
