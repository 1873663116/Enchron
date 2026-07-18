import Foundation
import RealityKit

struct PlaybackSurfaceTransform: Equatable, Sendable {
    let verticalOffset: Double
    let depthOffset: Double
    let viewAngle: Double
    let scale: Double
}

struct MacWindowPlaybackCameraGeometry: Equatable, Sendable {
    nonisolated static let fieldOfViewInDegrees: Float = 50
    nonisolated static let fillFraction: Float = 0.98

    nonisolated let screenSize: SIMD2<Float>
    nonisolated let distance: Float

    nonisolated static func resolve(
        screenSize: SIMD2<Float>,
        canvasSize: CGSize
    ) -> Self {
        let resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : SIMD2<Float>(16.0 / 9.0, 1)
        let canvasAspect = max(Float(canvasSize.width), 1)
            / max(Float(canvasSize.height), 1)
        let verticalTangent = tan(fieldOfViewInDegrees * .pi / 360)
        let verticalDistance = resolvedScreenSize.y / 2 / verticalTangent
        let horizontalDistance = resolvedScreenSize.x / 2 / (verticalTangent * canvasAspect)

        return Self(
            screenSize: resolvedScreenSize,
            distance: max(verticalDistance, horizontalDistance) / fillFraction
        )
    }
}

@MainActor
enum PlaybackSurfaceAnchorResolver {
    static let canonicalName = "PlaybackSurfaceAnchor"
    static let legacyName = "screen"

    static func resolve(in world: Entity) throws -> Entity {
        let anchor: Entity
        if let canonical = world.findEntity(named: canonicalName) {
            anchor = canonical
        } else if let legacy = world.findEntity(named: legacyName) {
            legacy.name = canonicalName
            anchor = legacy
        } else {
            throw PlaybackSurfaceError.missingAnchor
        }
        removePlaybackGeometry(from: anchor)
        return anchor
    }

    private static func removePlaybackGeometry(from entity: Entity) {
        entity.components.remove(ModelComponent.self)
        for child in entity.children {
            removePlaybackGeometry(from: child)
        }
    }
}

@MainActor
enum PlaybackSurfacePlacement {
    static func window(_ entity: Entity) {
        entity.position = .zero
        entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        entity.scale = .one
    }

    static func dock(
        _ entity: Entity,
        to anchor: Entity,
        transform: PlaybackSurfaceTransform
    ) {
        if entity.parent !== anchor {
            anchor.addChild(entity)
        }
        entity.position = [0, Float(transform.verticalOffset), Float(transform.depthOffset)]
        entity.orientation = simd_quatf(
            angle: Float(transform.viewAngle * .pi / 180),
            axis: [1, 0, 0]
        )
        entity.scale = .init(repeating: Float(transform.scale))
    }
}

enum PlaybackSurfaceError: LocalizedError {
    case missingAnchor

    var errorDescription: String? {
        "The selected environment does not contain PlaybackSurfaceAnchor."
    }
}
