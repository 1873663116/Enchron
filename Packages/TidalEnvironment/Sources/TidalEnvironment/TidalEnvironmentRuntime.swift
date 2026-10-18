import EnvironmentSceneContract
import Foundation
import Metal
import OSLog
import RealityKit
import simd

struct TidalRuntimeComponent: Component {
    let runtime: TidalEnvironmentRuntime
}

struct TidalMotionSystem: System {
    private static let query = EntityQuery(where: .has(TidalRuntimeComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[TidalRuntimeComponent.self]?.runtime.advance(by: context.deltaTime)
        }
    }
}

final class TidalEnvironmentRuntime {
    private final class Surface {
        weak var entity: Entity?
        let index: Int
        let highlights: [String: Float]
        let reflectionGain: Float?
        let hasSceneFrame: Bool
        let hasSky: Bool
        let hasDarkMix: Bool

        init(entity: Entity, index: Int, material: ShaderGraphMaterial) {
            self.entity = entity
            self.index = index
            var names: [String] = []
            if material.parameterNames.contains("GlassOpacity") {
                names = ["LampSpecularGain", "EdgeHighlightGain", "SkyReflectionGain"]
            } else if material.parameterNames.contains("GlassTintStrength") {
                names = ["HighlightStrength", "EnvironmentReflectionGain"]
            }
            highlights = names.reduce(into: [:]) { result, name in
                if case .float(let value)? = material.getParameter(name: name) { result[name] = value }
            }
            if case .float(let value)? = material.getParameter(name: "ScreenReflectionGain") {
                reflectionGain = value
            } else {
                reflectionGain = nil
            }
            hasSceneFrame = material.parameterNames.contains("SceneFrameOrigin")
            hasSky = material.parameterNames.contains("SkyOrientationAxis")
            hasDarkMix = material.parameterNames.contains("DarkMix")
        }
    }

    private let surfaces: [Surface]
    private weak var orbit: Entity?
    private weak var skyDome: Entity?
    private var skyBaseOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var timeline = TidalMotionTimeline()
    private var lastMix: Float?
    private let logger = Logger(subsystem: "com.xiongzhipeng.Enchron", category: "TidalMotion")

    init(root: Entity, template: ShaderGraphMaterial, darkTextures: [String: TextureResource]) throws {
        func hasParameter(_ entity: Entity, _ name: String) -> Bool {
            if entity.components[ModelComponent.self]?.materials.contains(where: {
                ($0 as? ShaderGraphMaterial)?.parameterNames.contains(name) == true
            }) == true { return true }
            return entity.children.contains { hasParameter($0, name) }
        }
        guard let skyDome = root.findEntity(named: "SkyDome") else {
            throw TidalDarkMaterial.Failure.missingParameter("SkyDome")
        }
        self.skyDome = skyDome
        self.skyBaseOrientation = skyDome.orientation
        for (entityName, parameter) in [
            ("PoolWater", "DarkMix"), ("PoolWater", "SkyOrientationAxis"),
            ("GlassPoolSide", "SkyOrientationAxis"), ("CartGlass350", "SkyOrientationAxis"), ("CartDrinkBottleBody", "SkyOrientationAxis")
        ] {
            guard let entity = root.findEntity(named: entityName), hasParameter(entity, parameter) else {
                throw TidalDarkMaterial.Failure.missingParameter(entityName + "." + parameter)
            }
        }
        var collected: [Surface] = []
        func collect(_ entity: Entity) throws {
            if var model = entity.components[ModelComponent.self] {
                for index in model.materials.indices {
                    guard var material = model.materials[index] as? ShaderGraphMaterial else { continue }
                    if case .textureResource(let atlas)? = material.getParameter(name: "SceneAtlas_color") {
                        let gain = material.getParameter(name: "EmissionGain") ?? .float(1)
                        material = template
                        try material.setParameter(name: "SceneAtlas_color", value: .textureResource(atlas))
                        try material.setParameter(name: "EmissionGain", value: gain)
                    }
                    for (name, texture) in darkTextures where material.parameterNames.contains(name) {
                        try material.setParameter(name: "Dark" + name, value: .textureResource(texture))
                    }
                    if material.parameterNames.contains("DarkMix") {
                        try material.setParameter(name: "DarkMix", value: .float(0))
                    }
                    model.materials[index] = material
                    let surface = Surface(entity: entity, index: index, material: material)
                    if surface.hasDarkMix || surface.hasSky || surface.hasSceneFrame
                        || surface.reflectionGain != nil || !surface.highlights.isEmpty {
                        collected.append(surface)
                    }
                }
                entity.components.set(model)
            }
            for child in entity.children { try collect(child) }
        }
        try collect(root)
        surfaces = collected
        let group = Entity()
        group.name = "TidalDebrisOrbit"
        root.addChild(group)
        var fragments: [Entity] = []
        func findFragments(_ entity: Entity) {
            if TidalScenePlacement.isFragment(entity.name) {
                fragments.append(entity)
                return
            }
            for child in entity.children { findFragments(child) }
        }
        findFragments(root)
        for fragment in fragments { fragment.setParent(group, preservingWorldTransform: true) }
        orbit = group
        write(timeline.sample)
    }

    func request(_ appearance: EnvironmentAppearance) {
        timeline.request(appearance)
        write(timeline.sample)
    }

    func advance(by delta: Double) {
        timeline.advance(by: delta)
        let sample = timeline.sample
        orbit?.orientation = simd_quatf(angle: sample.orbitYaw, axis: [0, 1, 0])
        write(sample)
    }

    private func write(_ sample: TidalMotionTimeline.Sample) {
        let sky = simd_quatf(angle: sample.skyYaw, axis: [0, 1, 0]) * skyBaseOrientation
        skyDome?.orientation = sky
        let changed = lastMix != sample.darkMix
        for surface in surfaces where surface.hasSky || changed {
            modify(surface) { material in
                if changed {
                    if surface.hasDarkMix {
                        try material.setParameter(name: "DarkMix", value: .float(sample.darkMix))
                    }
                    for (name, gain) in surface.highlights {
                        try material.setParameter(name: name, value: .float(gain * (1 - sample.darkMix + 0.15 * sample.darkMix)))
                    }
                }
                if surface.hasSky {
                    try material.setParameter(name: "SkyOrientationAxis", value: .simd3Float(sky.imag))
                    try material.setParameter(name: "SkyOrientationW", value: .float(sky.real))
                }
            }
        }
        lastMix = sample.darkMix
    }

    func updateScreen(_ screen: EnvironmentScreenState?, in root: Entity) {
        let orientation = root.orientation(relativeTo: nil)
        let position = root.position(relativeTo: nil)
        for surface in surfaces where surface.hasSceneFrame || surface.reflectionGain != nil {
            modify(surface) { material in
                if surface.hasSceneFrame {
                    try material.setParameter(name: "SceneFrameOrigin", value: .simd3Float(position))
                    try material.setParameter(name: "SceneFrameX", value: .simd3Float(orientation.act([1, 0, 0])))
                    try material.setParameter(name: "SceneFrameY", value: .simd3Float(orientation.act([0, 1, 0])))
                    try material.setParameter(name: "SceneFrameZ", value: .simd3Float(orientation.act([0, 0, 1])))
                }
                guard let gain = surface.reflectionGain else { return }
                try material.setParameter(name: "ScreenReflectionGain", value: .float(screen != nil ? gain : 0))
                if material.parameterNames.contains("ReflectionMode") {
                    try material.setParameter(name: "ReflectionMode", value: .float(0))
                }
                guard let screen, material.parameterNames.contains("ScreenCenter") else { return }
                try material.setParameter(name: "ScreenCenter", value: .simd3Float(root.convert(position: screen.center, from: nil)))
                try material.setParameter(name: "ScreenForward", value: .simd3Float(root.convert(direction: screen.normal, from: nil)))
                try material.setParameter(name: "ScreenHalfWidth", value: .float(screen.halfWidth))
                try material.setParameter(name: "ScreenHalfHeight", value: .float(screen.halfHeight))
            }
        }
    }

    func prewarm() async throws {
        var representatives: [String: ShaderGraphMaterial] = [:]
        for surface in surfaces {
            guard let material = surface.entity?.components[ModelComponent.self]?.materials[surface.index] as? ShaderGraphMaterial else { continue }
            let key = material.parameterNames.sorted().joined(separator: ",")
            representatives[key] = material
        }
        let renderer = try RealityRenderer()
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 90
        renderer.activeCamera = camera
        renderer.entities.append(camera)
        let mesh = MeshResource.generateBox(size: 0.1)
        guard let device = MTLCreateSystemDefaultDevice() else { throw TidalDarkMaterial.Failure.metalUnavailable }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 96, height: 96, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw TidalDarkMaterial.Failure.metalUnavailable }
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var longestSubmission = Duration.zero
        for value in representatives.values {
            try Task.checkCancellation()
            var material = value
            if material.parameterNames.contains("DarkMix") { try material.setParameter(name: "DarkMix", value: .float(0.5)) }
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = [0, 0, -1]
            renderer.entities.append(entity)
            for _ in 0..<3 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        let started = ContinuousClock.now
                        try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in continuation.resume() })
                        longestSubmission = max(longestSubmission, started.duration(to: .now))
                    } catch { continuation.resume(throwing: error) }
                }
            }
            renderer.entities.remove(entity)
            await Task.yield()
        }
        logger.notice("Prewarm materials=\(representatives.count) longestSubmission=\(String(describing: longestSubmission), privacy: .public)")
        renderer.entities.removeAll()
        renderer.activeCamera = nil
    }

    private func modify(_ surface: Surface, edit: (inout ShaderGraphMaterial) throws -> Void) {
        guard let entity = surface.entity, var model = entity.components[ModelComponent.self],
              var material = model.materials[surface.index] as? ShaderGraphMaterial else { return }
        do {
            try edit(&material)
            model.materials[surface.index] = material
            entity.components.set(model)
        } catch { logger.error("Material update failed: \(error.localizedDescription, privacy: .public)") }
    }
}
