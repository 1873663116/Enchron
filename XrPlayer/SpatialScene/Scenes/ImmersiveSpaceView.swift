import SwiftUI
import RealityKit
import RealityKitScripting

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) var appModel
    @Environment(PanoramaLayerBridge.self) var panoramaBridge

    @State private var sphereEntity: Entity?
    @State private var virtualScreenEntity: Entity?
    @State private var worldEntity: Entity?
    @State private var lastProjection: PanoramaProjection = .full360
    @State private var isLoadingWorld = false

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
                // Real RCP `world` scene (RealityKitScripting) replaces the
                // procedural dome. Entity(named:) searches the main bundle for a
                // scene named "world" inside Immersive_Space.reality. See ADR-0008.
                await addWorldScene(to: content)

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
                // Environment-expand browsing keeps playbackMode == .window but
                // opens the immersive space in mixed style to preview the RCP
                // `world` while the SenseZone volume stays visible (ENV-18). No
                // virtual screen here — this is scene preview, not playback.
                if appModel.isEnvironmentImmersiveActive {
                    await addWorldScene(to: content)
                }
            }
        } update: { content in
            switch appModel.playbackMode {
            case .panorama:
                if let entity = virtualScreenEntity {
                    content.remove(entity)
                    virtualScreenEntity = nil
                }
                if let entity = worldEntity {
                    content.remove(entity)
                    worldEntity = nil
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
                // Ensure the real `world` is present. It is loaded once
                // asynchronously, then re-attached if a later mode transition
                // detached it. All seven environment cards map to the same
                // `world` this round (see EnvironmentSceneMapping).
                if let world = worldEntity {
                    if world.parent == nil {
                        content.add(world)
                    }
                } else {
                    ensureWorldLoaded()
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
                // Keep the `world` while environment-expand browsing is active;
                // only tear it down when the immersive space is truly emptying.
                if appModel.isEnvironmentImmersiveActive {
                    if let world = worldEntity {
                        if world.parent == nil {
                            content.add(world)
                        }
                    } else {
                        ensureWorldLoaded()
                    }
                } else if let entity = worldEntity {
                    content.remove(entity)
                    worldEntity = nil
                }
                panoramaBridge.fisheyeRemapConfig = nil
                panoramaBridge.stereoCropMode = nil
            }
        }
        .realityScripting()
        .dragRotation(pitchLimit: .degrees(30), sensitivity: 10)
        // §5.9d: SpatialTapGesture to summon/dismiss player controls.
        // Entities already carry InputTargetComponent + CollisionComponent,
        // so the gesture is never silently dropped.
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appModel.showControls.toggle()
                    }
                    if appModel.showControls {
                        appModel.registerControlsInteraction()
                    }
                }
        )
    }

    /// Loads the RCP `world` scene and adds it to the immersive content. Used by
    /// the async `make` closure for both immersive playback and environment-expand
    /// browsing (the seven cards all map to the same `world` this round).
    @MainActor
    private func addWorldScene(to content: RealityViewContent) async {
        do {
            let world = try await Entity(named: "world")
            content.add(world)
            worldEntity = world
        } catch {
            assertionFailure("[ImmersiveSpaceView] failed to load RCP world: \(error)")
        }
    }

    /// Sync trigger for the `update` closure: kicks off an async load into
    /// `worldEntity`; the resulting state change re-runs `update`, which attaches
    /// the now-loaded entity.
    @MainActor
    private func ensureWorldLoaded() {
        guard worldEntity == nil, !isLoadingWorld else { return }
        isLoadingWorld = true
        Task { @MainActor in
            worldEntity = try? await Entity(named: "world")
            isLoadingWorld = false
        }
    }

    private func stereoModeForCurrentProjection() -> PlaybackCoreDomain.StereoLayout? {
        // effectiveStereoLayout respects user's 3D override (.mono = Off, nil auto-follows detected)
        let layout = appModel.effectiveStereoLayout
        return layout == .mono ? nil : layout
    }
}
