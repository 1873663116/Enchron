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
    static let dockCaptureRadians: Float = 12 * .pi / 180
    static let dockReleaseRadians: Float = 22 * .pi / 180

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
            let headToDock = Self.distance(from: head, to: dock)
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

    var dockPositionProvider: @MainActor () -> SIMD3<Float>? = { nil }

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
        let dockGaze = dockPositionProvider().map { dockPosition in
            LazyGazeFollow.gaze(of: dockPosition - headPosition)
        }
        follow.advance(
            head: LazyGazeFollow.Gaze(yaw: headGaze.yaw, pitch: headGaze.pitch),
            dock: dockGaze.map { LazyGazeFollow.Gaze(yaw: $0.yaw, pitch: $0.pitch) },
            deltaTime: deltaTime
        )
        root.position = headPosition
        root.orientation = follow.orientation
    }
}
