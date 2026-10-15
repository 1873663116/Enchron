import Foundation
import RealityKit
import Metal
@main struct RenderCheck {
    @MainActor static func main() async throws {
        let packed = try TidalDarkParameters.load(from: URL(fileURLWithPath: "Packages/TidalEnvironment/Sources/TidalEnvironment/Resources/dark-parameters.bin"))
        let root = try await Entity(contentsOf: URL(fileURLWithPath: "Packages/TidalEnvironment/Sources/TidalEnvironment/Resources/tidal.reality"))
        let light = root.findEntity(named: "BedroomDoorSillMesh")!.components[ModelComponent.self]!.materials[0] as! ShaderGraphMaterial
        guard case .textureResource(let atlas)? = light.getParameter(name: "SceneAtlas_color") else { fatalError() }
        print("atlas size=\(atlas.width)x\(atlas.height) format=\(atlas.pixelFormat.rawValue) mips=\(atlas.mipmapLevelCount)")
        let dark = try await TidalDarkMaterial.prepare(parameters: packed, lightTexture: atlas)
        let renderer = try RealityRenderer()
        renderer.cameraSettings.isToneMappingEnabled = false
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 90
        camera.position = [0,0,1]
        renderer.activeCamera = camera
        renderer.entities.append(camera)
        var mesh = MeshDescriptor()
        var positions: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var triangles: [UInt32] = []
        var points: [(Int,Int)] = []
        for i in 0..<64 {
            let edges = [(0,0), (16383,16383), (15,16), (16,15), (8191,8192), (8192,8191), (16383,0), (0,16383)]
            let x = i < edges.count ? edges[i].0 : (i * 7919 + 5701) % 16384
            let y = i < edges.count ? edges[i].1 : (i * 1543 + 8573) % 16384
            points.append((x,y))
            let left = Float(i % 8) / 4 - 1
            let top = 1 - Float(i / 8) / 4
            let base = UInt32(positions.count)
            positions += [[left,top-0.25,0],[left+0.25,top-0.25,0],[left,top,0],[left+0.25,top,0]]
            coordinates += Array(repeating: [Float(x)+0.5, 16384-Float(y)-0.5].simd / 16384, count: 4)
            triangles += [base,base+1,base+2,base+2,base+1,base+3]
        }
        mesh.positions = .init(positions)
        mesh.textureCoordinates = .init(coordinates)
        mesh.primitives = .triangles(triangles)
        let entity = ModelEntity(mesh: try MeshResource.generate(from: [mesh]), materials: [light])
        renderer.entities.append(entity)
        let device = MTLCreateSystemDefaultDevice()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 64, height: 64, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = device.makeTexture(descriptor: descriptor)!
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func render(_ material: ShaderGraphMaterial) async throws -> [[Float]] {
            entity.model!.materials = [material]
            for _ in 0..<3 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
                    do { try renderer.updateAndRender(deltaTime: 1/60, cameraOutput: output, onComplete: { _ in continuation.resume() }) }
                    catch { continuation.resume(throwing: error) }
                }
            }
            var bytes = [UInt16](repeating: 0, count: 64*64*4)
            texture.getBytes(&bytes, bytesPerRow: 64*8, from: .init(origin: .init(x: 0,y: 0,z: 0),size: .init(width:64,height:64,depth:1)), mipmapLevel: 0)
            return (0..<64).map { i in
                let offset = ((i/8*8+4)*64+i%8*8+4)*4
                return (0..<3).map { Float(Float16(bitPattern: bytes[offset+$0])) }
            }
        }
        let lightPixels = try await render(light)
        let darkPixels = try await render(dark)
        var blendErrors: [String: Float] = [:]
        for weight: Float in [0, 0.25, 0.5, 0.75, 1] {
            var blended = dark
            try blended.setParameter(name: "DarkMix", value: .float(weight))
            let pixels = try await render(blended)
            let error = (0..<64).flatMap { point in
                (0..<3).map { channel in
                    abs(pixels[point][channel] - (lightPixels[point][channel] * (1 - weight) + darkPixels[point][channel] * weight))
                }
            }.max()!
            blendErrors[String(weight)] = error
            if error >= 0.001 {
                try JSONSerialization.data(withJSONObject: ["weight": weight, "error": error, "source": lightPixels, "actual": pixels, "dark": darkPixels], options: [.prettyPrinted])
                    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("blend-failure.json"))
                throw NSError(domain: "TidalDissolveVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: "weight=\(weight), error=\(error)"])
            }
        }
        try JSONSerialization.data(withJSONObject: blendErrors, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("dissolve.json"))
        var rows: [[String:Any]] = []
        for (i,point) in points.enumerated() {
            let macro = (point.1/16*1024+point.0/16)*4
            let level = Int(packed.macroblocks[macro+3])
            let offset = Int(packed.macroblocks[macro]) + Int(packed.macroblocks[macro+1])*256 + Int(packed.macroblocks[macro+2])*65536
            let cells = 1<<level
            let slot = offset + ((point.1%16/(16/cells))*cells+point.0%16/(16/cells))*3
            let values: [Float] = packed.codes.withUnsafeBytes { raw in
                (0..<3).map { Float(Float16(bitPattern: raw.loadUnaligned(fromByteOffset:(slot+$0)*2,as:UInt16.self))) }
            }
            let expected = (0..<3).map { c in
                let absolute = values[c]>=1024
                let code = values[c] - (absolute ? 1024:0)
                return min(1,exp2(-14+code/1023*18)*(absolute ? 1:lightPixels[i][c]))
            }
            rows.append(["point":[point.0,point.1],"light":lightPixels[i],"actual":darkPixels[i],"expected":expected,"packed":values])
        }
        let data = try JSONSerialization.data(withJSONObject: rows,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        let error = rows.map { row in
            zip(row["actual"] as! [Float], row["expected"] as! [Float]).map { abs($0 - $1) }.max()!
        }.max()!
        guard error < 0.001 else { throw NSError(domain: "TidalGPUVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: "GPU error \(error)"]) }
        print("verified 64 source/decode samples, maximum linear error=\(error)")
    }
}
extension Array where Element == Float { var simd: SIMD2<Float> { SIMD2(self[0],self[1]) } }
