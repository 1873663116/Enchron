import CoreImage
import EnvironmentSceneContract
import Foundation
import Metal
import RealityKit

@main
struct TidalMotionGPUVerification {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resources = URL(fileURLWithPath: "Packages/TidalEnvironment/Sources/TidalEnvironment/Resources", isDirectory: true)
        let root = try await Entity(contentsOf: resources.appendingPathComponent("tidal.reality"))
        root.position.y += TidalScenePlacement.rootHeight
        for (name, offset) in TidalScenePlacement.debrisOffsets {
            let entity = root.findEntity(named: name)!
            entity.setPosition(entity.position(relativeTo: root) + offset, relativeTo: root)
        }
        root.disableEnvironmentPreviewScreen()
        let light = root.findEntity(named: "BedroomDoorSillMesh")!.components[ModelComponent.self]!.materials[0] as! ShaderGraphMaterial
        guard case .textureResource(let atlas)? = light.getParameter(name: "SceneAtlas_color") else { fatalError() }
        let parameters = try TidalDarkParameters.load(from: resources.appendingPathComponent("dark-parameters.bin"))
        let template = try await TidalDarkMaterial.prepare(parameters: parameters, lightTexture: atlas)
        var darkTextures: [String: TextureResource] = [:]
        for (parameter, file) in [("FloorPlane_color", "floor-dark"), ("WallLeftPlane_color", "wall-left-dark"), ("RecessPlane_color", "recess-dark")] {
            darkTextures[parameter] = try await TextureResource(contentsOf: resources.appendingPathComponent(file + ".ktx"), options: .init(semantic: .color))
        }
        let runtimeStart = ContinuousClock.now
        let runtime = try TidalEnvironmentRuntime(root: root, template: template, darkTextures: darkTextures)
        print("Runtime setup: \(runtimeStart.duration(to: .now))")
        let warmStart = ContinuousClock.now
        try await runtime.prewarm()
        print("Runtime prewarm: \(warmStart.duration(to: .now))")
        runtime.updateScreen(nil, in: root)
        var fragments: [String: SIMD3<Float>] = [:]
        func capture(_ entity: Entity) {
            if TidalScenePlacement.isFragment(entity.name) { fragments[entity.name] = entity.position(relativeTo: root) }
            for child in entity.children { capture(child) }
        }
        capture(root)
        let renderer = try RealityRenderer()
        renderer.cameraSettings.isToneMappingEnabled = false
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 75
        camera.position = [0, 1.6, 0]
        camera.orientation = simd_quatf(angle: -.pi / 10, axis: [1, 0, 0])
        renderer.activeCamera = camera
        renderer.entities.append(root)
        renderer.entities.append(camera)
        let device = MTLCreateSystemDefaultDevice()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1280, height: 720, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        let context = CIContext(mtlDevice: device)
        var times: [Double] = []
        var frameTimes: [String: [Double]] = [:]
        func render(_ name: String, deltaTime: Double = 0) async throws -> [Float] {
            for _ in 0..<3 {
                let start = ContinuousClock.now
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do { try renderer.updateAndRender(deltaTime: deltaTime, cameraOutput: output, onComplete: { _ in continuation.resume() }) }
                    catch { continuation.resume(throwing: error) }
                }
                let elapsed = start.duration(to: .now).components
                let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                times.append(milliseconds)
                frameTimes[name, default: []].append(milliseconds)
            }
            let image = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])!
            let upright = image.transformed(by: .init(translationX: 0, y: 720).scaledBy(x: 1, y: -1))
            try context.writePNGRepresentation(of: upright, to: directory.appendingPathComponent(name + ".png"), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            var bytes = [UInt16](repeating: 0, count: 1280 * 720 * 4)
            texture.getBytes(&bytes, bytesPerRow: 1280 * 8, from: .init(origin: .init(x: 0, y: 0, z: 0), size: .init(width: 1280, height: 720, depth: 1)), mipmapLevel: 0)
            let pixels = bytes.enumerated().compactMap { index, value in index % 4 == 3 ? nil : Float(Float16(bitPattern: value)) }
            precondition(pixels.allSatisfy(\.isFinite))
            return pixels
        }
        func mean(_ pixels: [Float]) -> Double { pixels.reduce(0) { $0 + Double($1) } / Double(pixels.count) }
        func material() -> ShaderGraphMaterial { root.findEntity(named: "BedroomDoorSillMesh")!.components[ModelComponent.self]!.materials[0] as! ShaderGraphMaterial }
        runtime.advance(by: 0)
        var rows: [[String: Double]] = []
        _ = try await render("prepared")
        runtime.request(.dark)
        for index in 0...12 {
            if index > 0 { runtime.advance(by: 0.1) }
            let pixels = try await render("dissolve-\(index)")
            let material = material()
            guard case .float(let weight)? = material.getParameter(name: "DarkMix"),
                  case .textureResource(let bound)? = material.getParameter(name: "SceneAtlas_color") else { fatalError() }
            precondition(bound === atlas)
            let t = Double(index) / 12
            precondition(abs(Double(weight) - t * t * (3 - 2 * t)) < 0.00001)
            precondition(mean(pixels) > 0.0001)
            rows.append(["time": Double(index) / 10, "weight": Double(weight), "mean": mean(pixels)])
        }
        runtime.request(.light)
        runtime.advance(by: 0.3)
        let before = material().getParameter(name: "DarkMix")
        runtime.request(.dark)
        precondition(material().getParameter(name: "DarkMix") == before)
        runtime.advance(by: 1.2)
        precondition(material().getParameter(name: "DarkMix") == .float(1))
        runtime.advance(by: 1800 - 2.7)
        var orbitError: Float = 0
        for (name, position) in fragments {
            let actual = root.findEntity(named: name)!.position(relativeTo: root)
            orbitError = max(orbitError, simd_length(actual - SIMD3<Float>(-position.x, position.y, -position.z)))
        }
        precondition(orbitError < 0.0001)
        TidalMotionSystem.registerSystem()
        root.components.set(TidalRuntimeComponent(runtime: runtime))
        runtime.request(.light)
        for index in 0..<5 { _ = try await render("system-\(index)", deltaTime: 0.1) }
        precondition(material().getParameter(name: "DarkMix") == .float(0))
        root.components.remove(TidalRuntimeComponent.self)
        let sky = root.findEntity(named: "SkyDome")!
        sky.setParent(nil, preservingWorldTransform: true)
        renderer.entities.removeAll()
        renderer.entities.append(sky)
        renderer.entities.append(camera)
        camera.orientation = .init(angle: 0, axis: [0, 1, 0])
        var model = sky.components[ModelComponent.self]!
        var skyMaterial = model.materials[0] as! ShaderGraphMaterial
        try skyMaterial.setParameter(name: "SkyYaw", value: .float(.pi / 2))
        try skyMaterial.setParameter(name: "SkyBlurAngle", value: .float(0))
        model.materials[0] = skyMaterial
        sky.components.set(model)
        let sharp = try await render("sky-sharp")
        try skyMaterial.setParameter(name: "SkyBlurAngle", value: .float(.pi * 1.5 / 1.2 / 120))
        model.materials[0] = skyMaterial
        sky.components.set(model)
        let blurred = try await render("sky-blurred")
        func gradient(_ pixels: [Float]) -> Double {
            var total = 0.0
            for row in 0..<720 {
                for column in 0..<1279 {
                    let i = (row * 1280 + column) * 3
                    for c in 0..<3 { total += Double(abs(pixels[i + c] - pixels[i + 3 + c])) }
                }
            }
            return total / Double(720 * 1279 * 3)
        }
        precondition(gradient(blurred) < gradient(sharp))
        precondition(mean(blurred) > mean(sharp) * 0.5 && mean(blurred) < mean(sharp) * 2)
        times.sort()
        let report: [String: Any] = ["system_driven_transition": true, "frames": rows, "frame_times_ms": frameTimes, "orbit_error_m": orbitError, "fragments": fragments.count,
                                   "sky_sharp_mean": mean(sharp), "sky_blurred_mean": mean(blurred),
                                   "sky_sharp_gradient": gradient(sharp), "sky_blurred_gradient": gradient(blurred),
                                   "median_frame_ms": times[times.count / 2], "maximum_frame_ms": times.last!]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("motion.json"))
        print("Motion GPU verification passed; median render ms=\(times[times.count / 2])")
    }
}
