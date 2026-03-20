import SwiftUI
import RealityKit

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) var appModel
    @Environment(PanoramaLayerBridge.self) var panoramaBridge

    @State private var sphereEntity: Entity?

    public init() {}

    public var body: some View {
        RealityView { content in
            let entity = PanoramaSphereEntity.makeEntity(
                textureResource: panoramaBridge.textureResource
            )
            content.add(entity)
            sphereEntity = entity
        } update: { _ in
            // Update the sphere texture when the bridge produces a new resource.
            guard let sphereEntity,
                  let textureResource = panoramaBridge.textureResource
            else {
                return
            }
            PanoramaSphereEntity.updateTexture(
                on: sphereEntity,
                textureResource: textureResource
            )
        }
    }
}
