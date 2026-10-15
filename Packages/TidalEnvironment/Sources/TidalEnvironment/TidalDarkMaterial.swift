import Foundation
import Metal
import RealityKit

@MainActor
enum TidalDarkMaterial {
    enum Failure: Error {
        case metalUnavailable
        case uploadFailed(String)
        case missingNode(String)
        case missingParameter(String)
    }

    static func prepare(parameters: TidalDarkParameters, lightTexture: TextureResource) async throws -> ShaderGraphMaterial {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Failure.metalUnavailable
        }
        let macroblocks = try await upload(
            parameters.macroblocks, width: 1024, height: 1024,
            format: .rgba8Unorm, bytesPerPixel: 4, device: device, queue: queue
        )
        let codes = try await upload(
            parameters.codes, width: TidalDarkParameters.tableWidth, height: parameters.tableHeight,
            format: .r16Float, bytesPerPixel: 2, device: device, queue: queue
        )
        let program = try await makeProgram(lightTexture: lightTexture, macroblocks: macroblocks, codes: codes)
        return ShaderGraphMaterial(program: program)
    }

    @concurrent
    private nonisolated static func makeProgram(
        lightTexture: TextureResource, macroblocks: TextureResource, codes: TextureResource
    ) async throws -> ShaderGraphMaterial.Program {
        let builder = try DecoderGraph()
        let graph = try builder.make()
        return try await ShaderGraphMaterial.Program(descriptor: .init(
            inferredFrom: graph,
            inputValues: [
                "SceneAtlas_color": .textureResource(lightTexture),
                "DarkMacroblocks": .textureResource(macroblocks),
                "DarkCodes": .textureResource(codes),
                "EmissionGain": .float(1),
                "DarkMix": .float(1)
            ]
        ))
    }

    private static func upload(
        _ data: Data, width: Int, height: Int, format: MTLPixelFormat,
        bytesPerPixel: Int, device: any MTLDevice, queue: any MTLCommandQueue
    ) async throws -> TextureResource {
        let texture = try LowLevelTexture(descriptor: .init(
            pixelFormat: format, width: width, height: height,
            mipmapLevelCount: 1, textureUsage: .shaderRead
        ))
        let buffer = data.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
        guard let buffer, let command = queue.makeCommandBuffer(),
              let encoder = command.makeBlitCommandEncoder() else { throw Failure.metalUnavailable }
        let destination = texture.replace(using: command)
        encoder.copy(
            from: buffer, sourceOffset: 0, sourceBytesPerRow: width * bytesPerPixel,
            sourceBytesPerImage: data.count, sourceSize: .init(width: width, height: height, depth: 1),
            to: destination, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            command.addCompletedHandler { completed in
                if let error = completed.error {
                    continuation.resume(throwing: Failure.uploadFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
            command.commit()
        }
        return try await TextureResource(from: texture)
    }

    private nonisolated final class DecoderGraph {
        struct Port {
            let node: String
            var output = "out"
        }

        let library = ShaderGraph.NodeLibrary(version: .default)
        let graph: ShaderGraph
        var serial = 0

        init() throws {
            graph = try ShaderGraph(
                named: "TidalRuntimeDecode",
                inputs: [
                    .init(name: "SceneAtlas_color", type: .texture),
                    .init(name: "DarkMacroblocks", type: .texture),
                    .init(name: "DarkCodes", type: .texture),
                    .init(name: "EmissionGain", type: .float),
                    .init(name: "DarkMix", type: .float)
                ],
                outputs: [.init(name: "surface", type: .surfaceShader)],
                nodeLibrary: library
            )
        }

        func input(_ name: String) -> Port { Port(node: graph.arguments.name, output: name) }

        func constant(_ value: ShaderGraph.Value) throws -> Port {
            serial += 1
            return Port(node: try graph.addNode(.init(name: "value\(serial)", data: .constant(value))))
        }

        func number(_ value: Float) throws -> Port { try constant(.float(value)) }

        func node(_ name: String, _ inputs: [String: Port] = [:]) throws -> Port {
            guard let definition = library.definition(named: name) else { throw Failure.missingNode(name) }
            serial += 1
            let key = try graph.addNode(.init(name: "node\(serial)", data: .definition(definition)))
            for (port, source) in inputs {
                try graph.connect(source.node, outputPort: source.output, to: key, inputPort: port)
            }
            return Port(node: key)
        }

        func binary(_ operation: String, _ first: Port, _ second: Port) throws -> Port {
            try node("ND_\(operation)_float", ["in1": first, "in2": second])
        }

        func floor(_ value: Port) throws -> Port { try node("ND_floor_float", ["in": value]) }

        func component(_ value: Port, dimension: Int, axis: String) throws -> Port {
            var separated = try node("ND_separate\(dimension)_vector\(dimension)", ["in": value])
            separated.output = "out\(axis)"
            return separated
        }

        func read(_ texture: String, x: Port, y: Port) throws -> Port {
            try node("ND_RealityKitTextureRead_vector4", [
                "file": input(texture),
                "x": node("ND_convert_float_integer", ["in": x]),
                "y": node("ND_convert_float_integer", ["in": y]),
                "lod": constant(.int(0))
            ])
        }

        func decode(x: Port, y: Port) throws -> Port {
            let macroX = try floor(binary("divide", x, number(16)))
            let macroY = try floor(binary("divide", y, number(16)))
            let metadata = try read("DarkMacroblocks", x: macroX, y: macroY)
            var bytes: [Port] = []
            for axis in ["x", "y", "z", "w"] {
                bytes.append(try floor(binary("add", binary("multiply", component(metadata, dimension: 4, axis: axis), number(255)), number(0.5))))
            }
            let start = try binary("add", binary("add", bytes[0], binary("multiply", bytes[1], number(256))), binary("multiply", bytes[2], number(65536)))
            let cellsPerAxis = try binary("power", number(2), bytes[3])
            let step = try binary("divide", number(16), cellsPerAxis)
            let cellX = try floor(binary("divide", binary("modulo", x, number(16)), step))
            let cellY = try floor(binary("divide", binary("modulo", y, number(16)), step))
            let slot = try binary("add", start, binary("multiply", binary("add", binary("multiply", cellY, cellsPerAxis), cellX), number(3)))
            let light = try read("SceneAtlas_color", x: x, y: y)
            var colors: [Port] = []
            for (channel, axis) in ["x", "y", "z"].enumerated() {
                let index = try binary("add", slot, number(Float(channel)))
                let packed = try component(read(
                    "DarkCodes", x: binary("modulo", index, number(4096)),
                    y: floor(binary("divide", index, number(4096)))
                ), dimension: 4, axis: "x")
                let absolute = try floor(binary("divide", packed, number(1024)))
                let code = try binary("subtract", packed, binary("multiply", absolute, number(1024)))
                let gain = try binary("power", number(2), binary("add", number(-14), binary("multiply", code, number(18 / 1023))))
                let source = try node("ND_mix_float", [
                    "bg": component(light, dimension: 4, axis: axis), "fg": number(1), "mix": absolute
                ])
                colors.append(try node("ND_clamp_float", ["in": binary("multiply", source, gain)]))
            }
            return try node("ND_combine3_vector3", ["in1": colors[0], "in2": colors[1], "in3": colors[2]])
        }

        func mix(_ first: Port, _ second: Port, amount: Port) throws -> Port {
            try node("ND_mix_vector3", ["bg": first, "fg": second, "mix": amount])
        }

        func make() throws -> ShaderGraph {
            let uv = try node("ND_texcoord_vector2")
            let u = try binary("modulo", component(uv, dimension: 2, axis: "x"), number(1))
            let v = try binary("modulo", component(uv, dimension: 2, axis: "y"), number(1))
            let x = try binary("subtract", binary("multiply", u, number(16384)), number(0.5))
            let y = try binary("subtract", binary("multiply", binary("subtract", number(1), v), number(16384)), number(0.5))
            let baseX = try floor(x)
            let baseY = try floor(y)
            let fractionX = try binary("subtract", x, baseX)
            let fractionY = try binary("subtract", y, baseY)
            func wrapped(_ value: Port, offset: Float) throws -> Port {
                try binary("modulo", binary("add", value, number(16384 + offset)), number(16384))
            }
            let x0 = try wrapped(baseX, offset: 0)
            let y0 = try wrapped(baseY, offset: 0)
            let x1 = try wrapped(baseX, offset: 1)
            let y1 = try wrapped(baseY, offset: 1)
            let top = try mix(decode(x: x0, y: y0), decode(x: x1, y: y0), amount: fractionX)
            let bottom = try mix(decode(x: x0, y: y1), decode(x: x1, y: y1), amount: fractionX)
            let decoded = try mix(top, bottom, amount: fractionY)
            let sampled = try node("ND_RealityKitTexture2D_vector4", [
                "file": input("SceneAtlas_color"), "texcoord": uv,
                "no_flip_v": constant(.bool(true)),
                "u_wrap_mode": constant(.string("repeat")),
                "v_wrap_mode": constant(.string("repeat")),
                "mip_filter": constant(.string("nearest"))
            ])
            let light = try node("ND_convert_vector4_vector3", ["in": sampled])
            let color = try mix(light, decoded, amount: input("DarkMix"))
            let emitted = try node("ND_multiply_vector3FA", ["in1": color, "in2": input("EmissionGain")])
            let surface = try node("ND_realitykit_unlit_surfaceshader", [
                "color": node("ND_convert_vector3_color3", ["in": emitted]),
                "applyPostProcessToneMap": constant(.bool(false))
            ])
            try graph.connect(surface.node, outputPort: surface.output, to: graph.results.name, inputPort: "surface")
            return graph
        }
    }
}
