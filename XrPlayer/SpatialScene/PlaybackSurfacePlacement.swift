import Foundation
import RealityKit

struct PlaybackSurfaceTransform: Equatable, Sendable {
    let verticalOffset: Double
    let depthOffset: Double
    let viewAngle: Double
    let scale: Double
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
