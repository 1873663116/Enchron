import Foundation
import RealityKit
import Metal
import CoreImage

@main
struct TidalVisualStabilityVerification {
    @MainActor
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let device = MTLCreateSystemDefaultDevice()!
        let context = CIContext(mtlDevice: device)
        var report: [String: [String: Double]] = [:]
        for (name, path) in [("before", CommandLine.arguments[1]), ("after", CommandLine.arguments[2])] {
            let root = try await Entity(contentsOf: URL(fileURLWithPath: path))
            root.findEntity(named: "ScreenPreview")?.isEnabled = false
            let renderer = try RealityRenderer()
            renderer.cameraSettings.isToneMappingEnabled = false
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 75
            renderer.activeCamera = camera
            renderer.entities.append(root)
            renderer.entities.append(camera)
            func configure(_ entity: Entity, values: [String: MaterialParameters.Value]) throws {
                if var model = entity.components[ModelComponent.self] {
                    for index in model.materials.indices {
                        guard var material = model.materials[index] as? ShaderGraphMaterial else { continue }
                        for (key, value) in values where material.parameterNames.contains(key) {
                            try material.setParameter(name: key, value: value)
                        }
                        model.materials[index] = material
                    }
                    entity.components.set(model)
                }
                for child in entity.children { try configure(child, values: values) }
            }
            func output(width: Int) throws -> (any MTLTexture, RealityRenderer.CameraOutput) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float, width: width, height: width * 9 / 16, mipmapped: false
                )
                descriptor.usage = [.renderTarget, .shaderRead]
                descriptor.storageMode = .shared
                let texture = device.makeTexture(descriptor: descriptor)!
                return (texture, try .init(.singleProjection(colorTexture: texture)))
            }
            func render(_ texture: any MTLTexture, _ output: RealityRenderer.CameraOutput, save: String? = nil) async throws -> [Float] {
                for _ in 0..<3 {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        do {
                            try renderer.updateAndRender(deltaTime: 0, cameraOutput: output,
                                onComplete: { _ in continuation.resume() })
                        } catch { continuation.resume(throwing: error) }
                    }
                }
                if let save {
                    let image = CIImage(mtlTexture: texture, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])!
                    let upright = image.transformed(by: .init(translationX: 0, y: CGFloat(texture.height)).scaledBy(x: 1, y: -1))
                    try context.writePNGRepresentation(of: upright, to: directory.appendingPathComponent(save),
                        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                }
                var pixels = [UInt16](repeating: 0, count: texture.width * texture.height * 4)
                texture.getBytes(&pixels, bytesPerRow: texture.width * 8,
                    from: .init(origin: .init(x: 0, y: 0, z: 0), size: .init(width: texture.width, height: texture.height, depth: 1)),
                    mipmapLevel: 0)
                return pixels.enumerated().compactMap { index, value in index % 4 == 3 ? nil : Float(Float16(bitPattern: value)) }
            }
            func difference(_ lhs: [Float], _ rhs: [Float]) -> Double {
                zip(lhs, rhs).reduce(0) { $0 + Double(abs($1.0 - $1.1)) } / Double(lhs.count)
            }
            try configure(root, values: ["ScreenReflectionGain": .float(0), "RippleSpeed": .float(0)])
            camera.orientation = simd_quatf(angle: -.pi / 10, axis: [1, 0, 0])
            let (waterTexture, waterOutput) = try output(width: 1280)
            let water = try await render(waterTexture, waterOutput, save: "\(name)-no-screen.png")
            try configure(root, values: ["ScreenCenter": .simd3Float([1000, 1000, 1000])])
            let reference = try await render(waterTexture, waterOutput)
            report[name] = ["disabled_screen_geometry_difference": difference(water, reference)]
            if name == "after" {
                let cameraRotation = camera.orientation
                func sceneFrame(_ rotation: simd_quatf, _ origin: SIMD3<Float>) throws {
                    root.orientation = rotation
                    root.position = origin
                    camera.orientation = rotation * cameraRotation
                    camera.position = origin
                    try configure(root, values: [
                        "SceneFrameOrigin": .simd3Float(origin),
                        "SceneFrameX": .simd3Float(rotation.act([1, 0, 0])),
                        "SceneFrameY": .simd3Float(rotation.act([0, 1, 0])),
                        "SceneFrameZ": .simd3Float(rotation.act([0, 0, 1]))
                    ])
                }
                for gain: Float in [0, 1] {
                    try configure(root, values: [
                        "ScreenReflectionGain": .float(gain), "ReflectionMode": .float(1),
                        "ScreenCenter": .simd3Float([-0.04144001, 2.1222639, -13.55])
                    ])
                    let fixed = try await render(waterTexture, waterOutput, save: "frame-0-screen-\(Int(gain)).png")
                    for degrees: Float in [25, 90] {
                        try sceneFrame(simd_quatf(angle: degrees * .pi / 180, axis: [1, 0, 0]), [0.4, 0.6, -0.2])
                        let rotated = try await render(waterTexture, waterOutput, save: "frame-\(Int(degrees))-screen-\(Int(gain)).png")
                        let error = difference(fixed, rotated)
                        report[name]?["scene_frame_difference_\(Int(degrees))_screen_\(Int(gain))"] = error
                        try sceneFrame(.init(angle: 0, axis: [0, 1, 0]), .zero)
                    }
                }
                try configure(root, values: ["ScreenReflectionGain": .float(0), "ReflectionMode": .float(0)])
                for glassName in ["CartGlass350", "CartDrinkBottleBody"] {
                    let glass = root.findEntity(named: glassName)!
                    let center = glass.visualBounds(relativeTo: nil).center
                    glass.setParent(nil, preservingWorldTransform: true)
                    renderer.entities.removeAll()
                    renderer.entities.append(glass)
                    renderer.entities.append(camera)
                    camera.look(at: center, from: center + [0, 0.04, 0.3], relativeTo: nil)
                    let light = try await render(waterTexture, waterOutput, save: "\(glassName)-light-highlights.png")
                    try configure(glass, values: ["LampSpecularGain": .float(0.15), "SkyReflectionGain": .float(0.15)])
                    let dark = try await render(waterTexture, waterOutput, save: "\(glassName)-dark-highlights.png")
                    try configure(glass, values: ["LampSpecularGain": .float(0), "SkyReflectionGain": .float(0)])
                    let unlit = try await render(waterTexture, waterOutput)
                    let lightContribution = difference(light, unlit)
                    let darkContribution = difference(dark, unlit)
                    report[name]?["\(glassName)_light_highlights"] = lightContribution
                    report[name]?["\(glassName)_dark_highlights"] = darkContribution
                    guard lightContribution > 0.000001, darkContribution < lightContribution * 0.2 else {
                        throw NSError(domain: "TidalGlassHighlightVerification", code: 1)
                    }
                }
            }
            let sky = root.findEntity(named: "SkyDome")!
            sky.setParent(nil, preservingWorldTransform: true)
            renderer.entities.removeAll()
            renderer.entities.append(sky)
            renderer.entities.append(camera)
            camera.position = .zero
            camera.orientation = .init()
            for width in [320, 640, 1280] {
                let (texture, output) = try output(width: width)
                let base = try await render(texture, output, save: "\(name)-sky-\(width).png")
                var total = 0.0
                for degrees: Float in [-0.02, -0.01, 0.01, 0.02] {
                    camera.orientation = simd_quatf(angle: degrees * .pi / 180, axis: [0, 1, 0])
                    total += difference(base, try await render(texture, output))
                }
                camera.orientation = .init()
                report[name]?["sky_jitter_difference_\(width)"] = total / 4
                report[name]?["sky_mean_\(width)"] = base.reduce(0) { $0 + Double($1) } / Double(base.count)
            }
            renderer.entities.removeAll()
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("visual-stability.json"))
        print(String(decoding: data, as: UTF8.self))
        guard let before = report["before"], let after = report["after"],
              before["disabled_screen_geometry_difference"]! > 0.00001,
              after["disabled_screen_geometry_difference"]! < 0.000001,
              after.filter({ $0.key.hasPrefix("scene_frame_difference_") }).values.allSatisfy({ $0 < 0.00005 }),
              [320, 640, 1280].allSatisfy({
                  after["sky_jitter_difference_\($0)"]! > 0
                      && after["sky_jitter_difference_\($0)"]! < before["sky_jitter_difference_\($0)"]! * 0.5
              }) else {
            throw NSError(domain: "TidalVisualStabilityVerification", code: 1)
        }
    }
}
