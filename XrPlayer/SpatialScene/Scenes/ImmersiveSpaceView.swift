import SwiftUI
import RealityKit

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) var appModel
    @Environment(PanoramaLayerBridge.self) var panoramaBridge

    @State private var sphereEntity: Entity?
    @State private var virtualScreenEntity: Entity?
    @State private var environmentDomeEntity: Entity?
    @State private var lastProjection: PanoramaProjection = .full360
    @State private var lastDomeEnvironment: SpatialSceneDomain.CinemaEnvironment?

    public init() {}

    public var body: some View {
        RealityView { content in
            switch appModel.playbackMode {
            case .panorama:
                let projection: PanoramaProjection = appModel.effectiveProjectionType.requiresHemisphereMesh ? .front180 : .full360
                let entity = PanoramaSphereEntity.makeEntity(
                    textureResource: panoramaBridge.textureResource,
                    projection: projection
                )
                content.add(entity)
                sphereEntity = entity
                // Configure fisheye remap when projection requires it
                if appModel.effectiveProjectionType.requiresFisheyeRemap {
                    panoramaBridge.fisheyeRemapConfig = SpatialSceneDomain.FisheyeRemapConfiguration()
                } else {
                    panoramaBridge.fisheyeRemapConfig = nil
                }
                // Configure stereo crop for SBS/OU panorama content
                panoramaBridge.stereoCropMode = stereoModeForCurrentProjection()

            case .immersive:
                let dome = EnvironmentDomeEntity.makeEntity(
                    environment: appModel.currentCinemaEnvironment
                )
                content.add(dome)
                environmentDomeEntity = dome
                lastDomeEnvironment = appModel.currentCinemaEnvironment
                await EnvironmentDomeEntity.loadSkyboxTexture(
                    on: dome,
                    environment: appModel.currentCinemaEnvironment
                )

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
                // Configure stereo crop for SBS/OU cinema content
                panoramaBridge.stereoCropMode = stereoModeForCurrentProjection()

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
                    lastDomeEnvironment = nil
                }
                let currentProjection: PanoramaProjection = appModel.effectiveProjectionType.requiresHemisphereMesh ? .front180 : .full360
                if currentProjection != lastProjection, let oldSphere = sphereEntity {
                    content.remove(oldSphere)
                    sphereEntity = nil
                    lastProjection = currentProjection
                }
                if sphereEntity == nil {
                    let projection: PanoramaProjection = appModel.effectiveProjectionType.requiresHemisphereMesh ? .front180 : .full360
                    let entity = PanoramaSphereEntity.makeEntity(
                        textureResource: panoramaBridge.textureResource,
                        projection: projection
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
                // Configure fisheye remap when projection requires it
                if appModel.effectiveProjectionType.requiresFisheyeRemap {
                    panoramaBridge.fisheyeRemapConfig = SpatialSceneDomain.FisheyeRemapConfiguration()
                } else {
                    panoramaBridge.fisheyeRemapConfig = nil
                }
                // Configure stereo crop for SBS/OU panorama content
                panoramaBridge.stereoCropMode = stereoModeForCurrentProjection()

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
                    lastDomeEnvironment = appModel.currentCinemaEnvironment
                    Task {
                        await EnvironmentDomeEntity.loadSkyboxTexture(
                            on: dome,
                            environment: appModel.currentCinemaEnvironment
                        )
                    }
                }
                if let dome = environmentDomeEntity,
                   appModel.currentCinemaEnvironment != lastDomeEnvironment {
                    lastDomeEnvironment = appModel.currentCinemaEnvironment
                    Task {
                        await EnvironmentDomeEntity.switchEnvironment(
                            on: dome,
                            to: appModel.currentCinemaEnvironment
                        )
                    }
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
                panoramaBridge.fisheyeRemapConfig = nil
                // Configure stereo crop for SBS/OU cinema content
                panoramaBridge.stereoCropMode = stereoModeForCurrentProjection()

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
                    lastDomeEnvironment = nil
                }
                panoramaBridge.fisheyeRemapConfig = nil
                panoramaBridge.stereoCropMode = nil
            }
        }
        .dragRotation(pitchLimit: .degrees(30), sensitivity: 10)
    }

    private func stereoModeForCurrentProjection() -> PlaybackCoreDomain.StereoLayout? {
        // effectiveStereoLayout respects user's 3D override (.mono = Off, nil auto-follows detected)
        let layout = appModel.effectiveStereoLayout
        return layout == .mono ? nil : layout
    }
}
