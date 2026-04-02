import SwiftUI
import RealityKit

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) var appModel
    @Environment(PanoramaLayerBridge.self) var panoramaBridge

    @State private var sphereEntity: Entity?
    @State private var virtualScreenEntity: Entity?
    @State private var environmentDomeEntity: Entity?

    public init() {}

    public var body: some View {
        RealityView { content in
            switch appModel.playbackMode {
            case .panorama:
                let entity = PanoramaSphereEntity.makeEntity(
                    textureResource: panoramaBridge.textureResource
                )
                content.add(entity)
                sphereEntity = entity

            case .immersive:
                let dome = EnvironmentDomeEntity.makeEntity(
                    environment: appModel.currentCinemaEnvironment
                )
                content.add(dome)
                environmentDomeEntity = dome

                let entity = VirtualScreenEntity.makeEntity(
                    textureResource: panoramaBridge.textureResource
                )
                VirtualScreenEntity.updatePosition(
                    on: entity,
                    distance: Float(appModel.screenDistance),
                    verticalOffset: Float(appModel.screenVerticalOffset),
                    viewAngle: Float(appModel.screenViewAngle)
                )
                content.add(entity)
                virtualScreenEntity = entity

            case .window:
                break
            }
        } update: { content in
            switch appModel.playbackMode {
            case .panorama:
                if let entity = virtualScreenEntity {
                    content.remove(entity)
                    virtualScreenEntity = nil
                }
                if let entity = environmentDomeEntity {
                    content.remove(entity)
                    environmentDomeEntity = nil
                }
                if sphereEntity == nil {
                    let entity = PanoramaSphereEntity.makeEntity(
                        textureResource: panoramaBridge.textureResource
                    )
                    content.add(entity)
                    sphereEntity = entity
                }
                if let sphereEntity,
                   let textureResource = panoramaBridge.textureResource {
                    PanoramaSphereEntity.updateTexture(
                        on: sphereEntity,
                        textureResource: textureResource
                    )
                }

            case .immersive:
                if let entity = sphereEntity {
                    content.remove(entity)
                    sphereEntity = nil
                }
                if environmentDomeEntity == nil {
                    let dome = EnvironmentDomeEntity.makeEntity(
                        environment: appModel.currentCinemaEnvironment
                    )
                    content.add(dome)
                    environmentDomeEntity = dome
                }
                if let dome = environmentDomeEntity {
                    EnvironmentDomeEntity.switchEnvironment(
                        on: dome,
                        to: appModel.currentCinemaEnvironment
                    )
                }
                if virtualScreenEntity == nil {
                    let entity = VirtualScreenEntity.makeEntity(
                        textureResource: panoramaBridge.textureResource,
                        geometry: appModel.screenShape
                    )
                    content.add(entity)
                    virtualScreenEntity = entity
                }
                if let virtualScreenEntity {
                    if let textureResource = panoramaBridge.textureResource {
                        VirtualScreenEntity.updateTexture(
                            on: virtualScreenEntity,
                            textureResource: textureResource
                        )
                    }
                    VirtualScreenEntity.switchGeometry(
                        on: virtualScreenEntity,
                        to: appModel.screenShape,
                        textureResource: panoramaBridge.textureResource
                    )
                    VirtualScreenEntity.updatePosition(
                        on: virtualScreenEntity,
                        distance: Float(appModel.screenDistance),
                        verticalOffset: Float(appModel.screenVerticalOffset),
                        viewAngle: Float(appModel.screenViewAngle)
                    )
                }

            case .window:
                if let entity = sphereEntity {
                    content.remove(entity)
                    sphereEntity = nil
                }
                if let entity = virtualScreenEntity {
                    content.remove(entity)
                    virtualScreenEntity = nil
                }
                if let entity = environmentDomeEntity {
                    content.remove(entity)
                    environmentDomeEntity = nil
                }
            }
        }
    }
}
