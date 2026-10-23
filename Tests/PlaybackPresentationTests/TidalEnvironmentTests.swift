import EnvironmentSceneContract
import Foundation
@testable import Playback
import RealityKit
import Metal
import Testing

@MainActor
struct TidalEnvironmentTests {
    @Test("Tidal blends appearances with one atlas and preserves water reflection gains")
    func appearanceRoundTrip() async throws {
        let scene = try #require(EnvironmentSceneMapping.scene(for: .tidal))
        let initialMemory = ProcessMemoryFootprint.read()?.footprintBytes ?? 0
        var peakMemory = initialMemory
        var longestTick = Duration.zero
        let memorySampler = Task { @MainActor in
            var previous = ContinuousClock.now
            while !Task.isCancelled {
                let now = ContinuousClock.now
                let tick = previous.duration(to: now)
                longestTick = max(longestTick, tick)
                if tick > .milliseconds(60) { print("Tidal mainActorGap=\(tick) at=\(Date())") }
                previous = now
                peakMemory = max(peakMemory, ProcessMemoryFootprint.read()?.footprintBytes ?? 0)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        defer { memorySampler.cancel() }
        let started = ContinuousClock.now
        EnvironmentSceneMapping.prefetch([.tidal], owner: EnvironmentPrefetchOwner("verification"))
        try await EnvironmentSceneMapping.waitForPrefetch(for: .tidal)
        var prepared: Task<Entity, Error>? = try #require(EnvironmentSceneMapping.takePrefetch(for: .tidal))
        var root: Entity? = try await prepared?.value
        prepared = nil
        let preparedFootprint = ProcessMemoryFootprint.read()?.footprintBytes ?? 0
        print("Tidal load: \(started.duration(to: .now)); footprint initial=\(initialMemory) peak=\(peakMemory) prepared=\(preparedFootprint); main actor longest tick=\(longestTick)")
        memorySampler.cancel()
        weak var releasedRoot = root
        let pose = try #require(scene.restPose)
        #expect(abs(pose.distance - 13.550063) < 0.01)
        #expect(abs(pose.center.y - 3.572264) < 0.01)
        #expect(pose.screenHeight == 8)
        #expect(abs(try #require(root).position.y - 0.8) < 0.0001)
        for elevation in [0.0, 30, 90] {
            let roomOrigin = try #require(root).position
            let tilted = PlaybackDockedPoseSolver.solve(
                transform: PlaybackSurfaceTransform(
                    distance: 13.550063, elevationDegrees: elevation, scale: 8, viewerHeight: 0
                ),
                geometry: scene.descriptor.geometry, restPose: pose,
                meshSize: [16, 9], roomOrigin: roomOrigin
            )
            let localScreen = tilted.roomRotation.inverse.act(tilted.center - tilted.roomPosition)
            #expect(simd_length(localScreen - (pose.center - roomOrigin)) < 0.001)
            #expect(simd_length(tilted.roomRotation.inverse.act(tilted.up) - pose.up) < 0.001)
        }
        do {
            let water = try #require(root?.findEntity(named: "PoolWater"))
            let clearance = pose.bottomHeight - water.visualBounds(relativeTo: nil).max.y
            #expect(clearance > 0.05 && clearance < 0.055)
        }
        let screen = EnvironmentScreenState(
            center: pose.center, right: pose.right, up: pose.up,
            halfWidth: pose.halfWidth, halfHeight: pose.halfHeight
        )
        func reflectionMaterials(in entity: Entity) -> [ShaderGraphMaterial] {
            let local = entity.components[ModelComponent.self]?.materials.compactMap {
                $0 as? ShaderGraphMaterial
            }.filter { $0.parameterNames.contains("ReflectionMode") } ?? []
            return local + entity.children.flatMap { reflectionMaterials(in: $0) }
        }
        for material in reflectionMaterials(in: try #require(root)) {
            #expect(material.getParameter(name: "ScreenReflectionGain") == .float(0))
        }
        scene.update(screen, in: try #require(root))
        let activeReflections = reflectionMaterials(in: try #require(root))
        #expect(!activeReflections.isEmpty)
        for material in activeReflections {
            #expect(material.getParameter(name: "ReflectionMode") == .float(0))
            if material.parameterNames.contains("PoolFrameOrigin") {
                #expect(material.getParameter(name: "ScreenReflectionGain") == .float(1))
            }
            #expect(material.getParameter(name: "ScreenCenter") == .simd3Float(try #require(root).convert(position: pose.center, from: nil)))
        }
        scene.update(nil, in: try #require(root))
        for material in reflectionMaterials(in: try #require(root)) {
            #expect(material.getParameter(name: "ScreenReflectionGain") == .float(0))
        }
        do {
            let entity = try #require(root)
            let transform = entity.transform
            let center = entity.convert(position: pose.center, from: nil)
            let rotation = simd_quatf(angle: 25 * .pi / 180, axis: SIMD3<Float>(1, 0, 0))
            entity.orientation = rotation
            entity.position = [0.4, 0.6, -0.2]
            scene.update(EnvironmentScreenState(
                center: entity.convert(position: center, to: nil),
                right: rotation.act(pose.right), up: rotation.act(pose.up),
                halfWidth: pose.halfWidth, halfHeight: pose.halfHeight
            ), in: entity)
            for material in reflectionMaterials(in: entity) {
                #expect(material.getParameter(name: "SceneFrameOrigin") == .simd3Float([0.4, 0.6, -0.2]))
                guard case .simd3Float(let up)? = material.getParameter(name: "SceneFrameY") else {
                    Issue.record("Reflection lost its scene orientation")
                    continue
                }
                #expect(simd_length(up - rotation.act([0, 1, 0])) < 0.0001)
                guard case .simd3Float(let actual)? = material.getParameter(name: "ScreenCenter") else {
                    Issue.record("Reflection lost its local screen position")
                    continue
                }
                #expect(simd_length(actual - center) < 0.0001)
            }
            entity.transform = transform
            scene.update(nil, in: entity)
        }
        var surfaces: [(Entity, Int, String, TextureResource)] = []
        var highlights: [(Entity, Int, String, Float)] = []
        func collect(_ entity: Entity) {
            if let model = entity.components[ModelComponent.self] {
                for (index, value) in model.materials.enumerated() {
                    guard let material = value as? ShaderGraphMaterial else { continue }
                    var parameters = material.parameterNames.contains("PoolFrameOrigin")
                        ? [] : ["LampSpecularGain", "EdgeHighlightGain", "HighlightStrength"]
                    if material.parameterNames.contains("GlassOpacity") { parameters.append("SkyReflectionGain") }
                    if material.parameterNames.contains("HighlightStrength") { parameters.append("EnvironmentReflectionGain") }
                    for parameter in parameters {
                        if case .float(let strength)? = material.getParameter(name: parameter) {
                            highlights.append((entity, index, parameter, strength))
                        }
                    }
                    for parameter in ["SceneAtlas_color", "FloorPlane_color", "WallLeftPlane_color", "RecessPlane_color"] {
                        if case .textureResource(let texture)? = material.getParameter(name: parameter) {
                            surfaces.append((entity, index, parameter, texture))
                        }
                    }
                }
            }
            for child in entity.children { collect(child) }
        }
        collect(try #require(root))
        #expect(surfaces.count > 100)
        #expect(highlights.contains { $0.3 > 0 })
        #expect(Set(surfaces.map { $0.2 }) == ["SceneAtlas_color", "FloorPlane_color", "WallLeftPlane_color", "RecessPlane_color"])
        let renderer = try RealityRenderer()
        renderer.cameraSettings.isToneMappingEnabled = false
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 75
        camera.position = [0, 1.6, 0]
        camera.orientation = simd_quatf(angle: -.pi / 10, axis: [1, 0, 0])
        renderer.activeCamera = camera
        renderer.entities.append(try #require(root))
        renderer.entities.append(camera)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 1280, height: 720, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func renderedMean(_ appearance: String, deltaTime: Double = 1 / 90, frames: Int = 12) async throws -> Double {
            var times: [Double] = []
            for frame in 0..<frames {
                let started = ContinuousClock.now
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do {
                        try renderer.updateAndRender(deltaTime: deltaTime, cameraOutput: output, onComplete: { _ in continuation.resume() })
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                let elapsed = started.duration(to: .now).components
                if frame > 2 { times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15) }
            }
            times.sort()
            print("Tidal \(appearance) rendered medianMS=\(times[times.count / 2]) maxMS=\(times.last ?? 0) footprint=\(ProcessMemoryFootprint.read()?.footprintBytes ?? 0)")
            var pixels = [UInt16](repeating: 0, count: 1280 * 720 * 4)
            texture.getBytes(&pixels, bytesPerRow: 1280 * 8, from: .init(
                origin: .init(x: 0, y: 0, z: 0), size: .init(width: 1280, height: 720, depth: 1)
            ), mipmapLevel: 0)
            var total: Double = 0
            for index in pixels.indices where index % 4 != 3 {
                total += Double(Float16(bitPattern: pixels[index]))
            }
            return total / Double(1280 * 720 * 3)
        }
        let lightMean = try await renderedMean("light")
        let switchStarted = ContinuousClock.now
        scene.apply(.dark, to: try #require(root))
        for _ in 0..<20 { scene.advance(0.1, in: try #require(root)) }
        let darkMean = try await renderedMean("dark", deltaTime: 0.1, frames: 15)
        do {
            let water = try #require(root?.findEntity(named: "PoolWater"))
            let material = try #require(reflectionMaterials(in: water).first)
            #expect(material.getParameter(name: "LampSpecularGain") == .float(1))
            #expect(material.getParameter(name: "SkyReflectionGain") == .float(1))
            #expect(material.getParameter(name: "ReflectionStrength") == .float(2.35))
        }
        for (entity, index, parameter, light) in highlights {
            let material = try #require(entity.components[ModelComponent.self]?.materials[index] as? ShaderGraphMaterial)
            let actual = material.getParameter(name: parameter)
            #expect(
                actual == .float(light * 0.15),
                "highlight \(parameter) light=\(light) actual=\(String(describing: actual)) entity=\(entity.name)"
            )
        }
        print("Tidal deep appearance: \(switchStarted.duration(to: .now))")
        for (entity, index, parameter, light) in surfaces {
            let graph = try #require(entity.components[ModelComponent.self]?.materials[index] as? ShaderGraphMaterial)
            guard case .textureResource(let dark)? = graph.getParameter(name: parameter) else {
                Issue.record("Dark appearance lost its atlas")
                continue
            }
            if parameter == "SceneAtlas_color" {
                #expect(dark === light)
                #expect(graph.parameterNames.contains("DarkMacroblocks"))
                #expect(graph.parameterNames.contains("DarkCodes"))
                guard case .textureResource(let codes)? = graph.getParameter(name: "DarkCodes"),
                      case .textureResource(let macroblocks)? = graph.getParameter(name: "DarkMacroblocks") else {
                    Issue.record("Runtime decode parameters were not bound")
                    continue
                }
                #expect(codes.width == 4096 && codes.height == 3604)
                #expect(macroblocks.width == 1024 && macroblocks.height == 1024)
            } else {
                #expect(dark === light)
                guard case .textureResource(let target)? = graph.getParameter(name: "Dark" + parameter) else {
                    Issue.record("Water appearance lost its dark texture")
                    continue
                }
                #expect(target !== light)
            }
        }
        #expect(lightMean > darkMean)
        #expect(darkMean > 0)
        scene.apply(.light, to: try #require(root))
        for _ in 0..<20 { scene.advance(0.1, in: try #require(root)) }
        _ = try await renderedMean("light-restored", deltaTime: 0.1, frames: 15)
        for (entity, index, parameter, light) in highlights {
            let material = try #require(entity.components[ModelComponent.self]?.materials[index] as? ShaderGraphMaterial)
            #expect(material.getParameter(name: parameter) == .float(light))
        }
        for (entity, index, parameter, light) in surfaces {
            let graph = try #require(entity.components[ModelComponent.self]?.materials[index] as? ShaderGraphMaterial)
            guard case .textureResource(let restored)? = graph.getParameter(name: parameter) else {
                Issue.record("Light appearance lost its atlas")
                continue
            }
            #expect(restored === light)
        }
        renderer.entities.removeAll()
        renderer.activeCamera = nil
        surfaces.removeAll()
        highlights.removeAll()
        root = nil
        #expect(releasedRoot == nil)
    }
}
