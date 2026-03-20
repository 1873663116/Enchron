import SwiftUI
import RealityKit

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) var appModel
    @Environment(PanoramaLayerBridge.self) var panoramaBridge

    @State private var sphereEntity: Entity?

    public init() {}

    public var body: some View {
        RealityView { content in
            if appModel.playbackMode == .panorama {
                let entity = PanoramaSphereEntity.makeEntity(
                    textureResource: panoramaBridge.textureResource
                )
                content.add(entity)
                sphereEntity = entity
            }
            // .immersive mode: space is open but no custom entity needed yet.
            // Future: add a flat virtual-screen entity for cinema-style immersive playback.
        } update: { content in
            switch appModel.playbackMode {
            case .panorama:
                // Ensure sphere exists.
                if sphereEntity == nil {
                    let entity = PanoramaSphereEntity.makeEntity(
                        textureResource: panoramaBridge.textureResource
                    )
                    content.add(entity)
                    sphereEntity = entity
                }
                // Update texture when bridge produces new frames.
                if let sphereEntity,
                   let textureResource = panoramaBridge.textureResource {
                    PanoramaSphereEntity.updateTexture(
                        on: sphereEntity,
                        textureResource: textureResource
                    )
                }

            case .immersive:
                // Remove panorama sphere if we switched away from panorama.
                if let entity = sphereEntity {
                    content.remove(entity)
                    sphereEntity = nil
                }

            case .window:
                // Should not happen (space dismissed before reaching window mode),
                // but clean up defensively.
                if let entity = sphereEntity {
                    content.remove(entity)
                    sphereEntity = nil
                }
            }
        }
    }
}
