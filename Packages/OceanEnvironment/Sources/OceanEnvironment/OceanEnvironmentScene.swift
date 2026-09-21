import EnvironmentSceneContract
import Foundation
import RealityKit
import simd

/// Bumped whenever app code writes into the ocean material source or sky dome.
/// OceanProbeSystem uses it to skip parameter synchronization on frames where
/// nothing changed.
@MainActor
enum OceanMaterialSyncEpoch {
    static var value: UInt64 = 0
    static func bump() { value &+= 1 }
}

@MainActor
public final class OceanEnvironmentScene: EnvironmentScene {
    public static let resourceName = "ocean"
    public static let worldEntityName = "world"
    public static let skyDomeEntityName = "OceanSkyDome"
    public static let softLightEntityName = "OceanSoftLight"
    public static let materialSourceEntityName = "OceanMaterialSource"
    public static let skyGainParameter = "SkyGain"
    public static let screenCenterXParameter = "ScreenCenterX"
    public static let screenCenterYParameter = "ScreenCenterY"
    public static let screenCenterZParameter = "ScreenCenterZ"
    public static let screenHalfWidthParameter = "ScreenHalfWidth"
    public static let screenHalfHeightParameter = "ScreenHalfHeight"
    public static let screenRightXParameter = "ScreenRightX"
    public static let screenRightZParameter = "ScreenRightZ"
    public static let videoTextureParameter = "VideoTexture"
    public static let reflectionStrengthParameter = "ReflectionStrength"
    public static let areaLightStrengthParameter = "AreaLightStrength"

    public nonisolated static let descriptor = EnvironmentSceneDescriptor(
        identifier: "ocean",
        geometry: EnvironmentSceneGeometry(
            ceilingHeightMeters: nil,
            distanceStrategy: .movesViewer,
            defaultDistanceMeters: 20,
            distanceRangeMeters: 12...47,
            defaultScreenHeightMeters: 20,
            screenHeightRangeMeters: 20...20,
            defaultViewerHeightMeters: 0,
            viewerHeightRangeMeters: -3...5,
            elevationRangeDegrees: 0...90,
            dimsSurroundings: true
        ),
        supportsDarkAppearance: true
    )

    public static let authoredSimulation = OceanProbeComponent(
        isEnabled: true,
        seed: 28,
        amplitude: 1.1,
        timeScale: 0.5,
        windSpeed: 5,
        windDirectionDegrees: 180,
        fetch: 8000,
        windAlignment: 0.75,
        crossSeaAmount: 0.5,
        crossSeaAngleDegrees: 37.242256,
        swellDirectionDegrees: 165,
        swellWavelength: 120,
        swellHeight: 0.4,
        swellSpread: 15,
        swellBandwidth: 0.18,
        waterDepth: 50,
        choppiness: 1.3,
        repeatTime: 200,
        foamBias: 0.2,
        foamPower: 1,
        foamAmount: 0.01,
        foamDecay: 0.1,
        lengthScale0: 1000,
        lengthScale1: 97,
        lengthScale2: 31,
        lengthScale3: 10.5,
        envelopeAmount: 0.35,
        envelopeScaleMeters: 2500,
        iblIntensityExponent: 0
    )

    private static var runtimeIsRegistered = false
    private static let authoredScreenHeightMeters: Float = 16

    private struct AuthoredLighting {
        var skyGain: Float
        var lightIntensity: Float
        var reflectionStrength: Float
        var areaLightStrength: Float
    }

    private struct MaterialWriteSignature: Equatable {
        var hasScreen: Bool
        var center: SIMD3<Float>
        var halfWidth: Float
        var halfHeight: Float
        var right: SIMD2<Float>?
        var reflectionStrength: Float
        var areaLightStrength: Float
        var videoTextureID: ObjectIdentifier?
    }

    private var authoredLighting: AuthoredLighting?
    private var lastMaterialWrite: MaterialWriteSignature?
    private var lastMaterialSource: ObjectIdentifier?

    public private(set) var restPose: EnvironmentScreenRestPose?
    private let audio = OceanEnvironmentAudio(
        swellWavelength: OceanEnvironmentScene.authoredSimulation.swellWavelength,
        waterDepth: OceanEnvironmentScene.authoredSimulation.waterDepth
    )

    public init() {}

    public var descriptor: EnvironmentSceneDescriptor { Self.descriptor }

    public static func registerRuntimeIfNeeded() {
        guard runtimeIsRegistered == false else { return }
        runtimeIsRegistered = true
        OceanProbeApplicationRuntime.register(environmentTextureBundle: .module)
        SkyRotationSystem.registerSystem()
    }

    public func load() async throws -> Entity {
        Self.registerRuntimeIfNeeded()
        guard let url = Bundle.module.url(forResource: Self.resourceName, withExtension: "reality") else {
            throw EnvironmentSceneLoadingError.resourceMissing(Self.resourceName)
        }
        let root = try await Entity(contentsOf: url)
        guard var pose = EnvironmentScreenRestPose.dockingRegion(
            in: root,
            screenHeight: Self.authoredScreenHeightMeters
        ) else {
            throw EnvironmentSceneLoadingError.entityMissing(EnvironmentSceneEntityName.dockingRegion)
        }
        let halfHeight = Float(Self.descriptor.geometry.defaultScreenHeightMeters) / 2
        pose.center.y += halfHeight - pose.halfHeight
        pose.halfWidth *= halfHeight / pose.halfHeight
        pose.halfHeight = halfHeight
        restPose = pose
        await audio.prepare(in: root, restPose: pose, bundle: .module)
        guard root.findEntity(named: Self.materialSourceEntityName) != nil else {
            throw EnvironmentSceneLoadingError.entityMissing(Self.materialSourceEntityName)
        }
        let world = root.name == Self.worldEntityName
            ? root
            : root.findEntity(named: Self.worldEntityName) ?? root
        world.components.set(Self.authoredSimulation)
        root.disableEnvironmentPreviewScreen()
        SkyRotation.install(in: root)
        authoredLighting = captureAuthoredLighting(in: root)
        return root
    }

    public func apply(_ appearance: EnvironmentAppearance, to root: Entity) {
        let authored = authoredLighting ?? captureAuthoredLighting(in: root)
        authoredLighting = authored
        let brightness = max(0, appearance.brightness)
        if let dome = root.findEntity(named: Self.skyDomeEntityName),
           var model = dome.components[ModelComponent.self],
           var sky = model.materials.first as? ShaderGraphMaterial {
            try? sky.setParameter(name: Self.skyGainParameter, value: .float(authored.skyGain * brightness))
            model.materials[0] = sky
            dome.components.set(model)
        }
        if let light = root.findEntity(named: Self.softLightEntityName),
           var component = light.components[DirectionalLightComponent.self] {
            component.intensity = authored.lightIntensity * brightness
            light.components.set(component)
        }
        OceanMaterialSyncEpoch.bump()
    }

    public func update(_ screen: EnvironmentScreenState?, in root: Entity) {
        let authored = authoredLighting ?? captureAuthoredLighting(in: root)
        authoredLighting = authored
        audio.startIfNeeded()
        if let screen {
            root.alignDockingRegion(to: screen)
        }
        guard let source = root.findEntity(named: Self.materialSourceEntityName),
              var model = source.components[ModelComponent.self],
              var material = model.materials.first as? ShaderGraphMaterial else {
            return
        }
        var signature = MaterialWriteSignature(
            hasScreen: screen != nil,
            center: screen?.center ?? .zero,
            halfWidth: screen?.halfWidth ?? 0,
            halfHeight: screen?.halfHeight ?? 0,
            right: nil,
            reflectionStrength: screen != nil ? authored.reflectionStrength : 0,
            areaLightStrength: screen != nil ? authored.areaLightStrength : 0,
            videoTextureID: screen?.videoTexture.map { ObjectIdentifier($0) }
        )
        var normalizedRight: SIMD2<Float>?
        if let screen {
            let horizontalRight = SIMD2<Float>(screen.right.x, screen.right.z)
            if simd_length(horizontalRight) > 1e-4 {
                normalizedRight = simd_normalize(horizontalRight)
            }
            signature.right = normalizedRight
        }
        guard lastMaterialWrite != signature
            || lastMaterialSource != ObjectIdentifier(source) else {
            return
        }
        if let screen {
            try? material.setParameter(name: Self.screenCenterXParameter, value: .float(screen.center.x))
            try? material.setParameter(name: Self.screenCenterYParameter, value: .float(screen.center.y))
            try? material.setParameter(name: Self.screenCenterZParameter, value: .float(screen.center.z))
            try? material.setParameter(name: Self.screenHalfWidthParameter, value: .float(screen.halfWidth))
            try? material.setParameter(name: Self.screenHalfHeightParameter, value: .float(screen.halfHeight))
            if let normalizedRight {
                try? material.setParameter(name: Self.screenRightXParameter, value: .float(normalizedRight.x))
                try? material.setParameter(name: Self.screenRightZParameter, value: .float(normalizedRight.y))
            }
            try? material.setParameter(name: Self.reflectionStrengthParameter, value: .float(authored.reflectionStrength))
            try? material.setParameter(name: Self.areaLightStrengthParameter, value: .float(authored.areaLightStrength))
            if let texture = screen.videoTexture {
                try? material.setParameter(name: Self.videoTextureParameter, value: .textureResource(texture))
            }
        } else {
            try? material.setParameter(name: Self.reflectionStrengthParameter, value: .float(0))
            try? material.setParameter(name: Self.areaLightStrengthParameter, value: .float(0))
        }
        model.materials[0] = material
        source.components.set(model)
        lastMaterialWrite = signature
        lastMaterialSource = ObjectIdentifier(source)
        OceanMaterialSyncEpoch.bump()
    }

    public func setVideoPlaying(_ isPlaying: Bool, in root: Entity) {
        audio.setVideoPlaying(isPlaying)
    }

    /// Builds the runtime IBL resource from an already-decoded root so the
    /// first `OceanProbeSystem.update` finds it cached. No-op without a sky
    /// dome material; `synchronize` then builds on demand as before.
    public func prewarmRuntime(in root: Entity) {
        guard let dome = root.findEntity(named: Self.skyDomeEntityName),
              let model = dome.components[ModelComponent.self],
              let sky = model.materials.first as? ShaderGraphMaterial
        else {
            return
        }
        RuntimeEnvironmentLighting.prewarm(sky: SkyAppearance(material: sky))
    }

    private func captureAuthoredLighting(in root: Entity) -> AuthoredLighting {
        var lighting = AuthoredLighting(
            skyGain: 1,
            lightIntensity: 1200,
            reflectionStrength: 1,
            areaLightStrength: 1
        )
        if let dome = root.findEntity(named: Self.skyDomeEntityName),
           let sky = dome.components[ModelComponent.self]?.materials.first as? ShaderGraphMaterial,
           case .float(let gain)? = sky.getParameter(name: Self.skyGainParameter) {
            lighting.skyGain = gain
        }
        if let light = root.findEntity(named: Self.softLightEntityName),
           let component = light.components[DirectionalLightComponent.self] {
            lighting.lightIntensity = component.intensity
        }
        if let source = root.findEntity(named: Self.materialSourceEntityName),
           let material = source.components[ModelComponent.self]?.materials.first as? ShaderGraphMaterial {
            if case .float(let strength)? = material.getParameter(name: Self.reflectionStrengthParameter) {
                lighting.reflectionStrength = strength
            }
            if case .float(let strength)? = material.getParameter(name: Self.areaLightStrengthParameter) {
                lighting.areaLightStrength = strength
            }
        }
        return lighting
    }
}
