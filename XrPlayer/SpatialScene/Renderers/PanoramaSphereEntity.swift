import RealityKit
import UIKit

/// Projection style that determines the sphere mesh geometry.
/// 360° uses a full sphere; 180° uses the front hemisphere only.
enum PanoramaProjection {
    case full360
    case front180
}

/// Creates a sphere entity whose normals are flipped inward so that a
/// video texture renders on the *inside* surface — the standard approach
/// for equirectangular 360 / 180 panorama playback.
///
/// The material uses `UnlitMaterial` with `applyPostProcessToneMap: false`
/// because the video frames have already been colour-processed by mpv;
/// RealityKit must not apply additional tone mapping.
enum PanoramaSphereEntity {

    /// Sphere radius in metres. 10 m gives comfortable viewing distance
    /// in a visionOS ImmersiveSpace.
    static let defaultRadius: Float = 10.0

    /// Creates a sphere entity ready for panorama video display.
    ///
    /// - Parameters:
    ///   - textureResource: The `TextureResource` exposed by the active
    ///     panorama bridge. Pass `nil` to create the entity without a
    ///     texture during bridge startup.
    ///   - projection: `.full360` for equirectangular 360° content,
    ///     `.front180` for 180° content (front hemisphere only).
    ///     Defaults to `.full360`.
    /// - Returns: A configured `Entity` with an inverted sphere mesh.
    static func makeEntity(
        textureResource: TextureResource?,
        projection: PanoramaProjection = .full360,
        radius: Float = defaultRadius
    ) -> Entity {
        let mesh: MeshResource
        switch projection {
        case .full360:
            mesh = MeshResource.generateSphere(radius: radius)
        case .front180:
            let config = SpatialSceneDomain.HemisphereMeshConfiguration(radius: radius)
            do {
                mesh = try generateHemisphereMesh(
                    radius: config.radius,
                    stacks: config.stacks,
                    slices: config.slices
                )
            } catch {
                print("[PanoramaSphere] hemisphere_mesh_failed error=\(error), falling back to full sphere")
                mesh = MeshResource.generateSphere(radius: radius)
            }
        }

        var material = UnlitMaterial(applyPostProcessToneMap: false)
        if let textureResource {
            material.color = .init(
                tint: .white,
                texture: .init(textureResource)
            )
        }

        let entity = Entity()
        entity.components.set(ModelComponent(mesh: mesh, materials: [material]))

        // Flip X scale to invert normals → texture renders on the inside.
        entity.scale.x *= -1

        return entity
    }

    /// Generates a custom hemisphere mesh covering the front 180° field of view.
    ///
    /// - Parameters:
    ///   - radius: Sphere radius in metres.
    ///   - stacks: Number of vertical subdivisions (latitude).
    ///   - slices: Number of horizontal subdivisions (longitude).
    /// - Returns: A `MeshResource` representing the front hemisphere.
    ///
    /// Longitude spans -π/2 to π/2 (front hemisphere).
    /// Latitude spans -π/2 to π/2 (full vertical range).
    /// UV mapping covers 0...1 in both axes so the full texture maps
    /// onto the hemisphere surface.
    static func generateHemisphereMesh(
        radius: Float,
        stacks: Int = 64,
        slices: Int = 64
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []

        for stack in 0...stacks {
            let v = Float(stack) / Float(stacks)        // 0...1
            let lat = Float.pi / 2 - v * Float.pi       // π/2 to -π/2 (top to bottom)

            for slice in 0...slices {
                let u = Float(slice) / Float(slices)     // 0...1
                let lon = -Float.pi / 2 + u * Float.pi   // -π/2 to π/2 (front hemisphere)

                let x = radius * cos(lat) * sin(lon)
                let y = radius * sin(lat)
                let z = radius * cos(lat) * cos(lon)

                positions.append(SIMD3(x, y, z))
                normals.append(normalize(SIMD3(x, y, z)))
                uvs.append(SIMD2(u, 1.0 - v))  // flip V for correct orientation
            }
        }

        // Standard grid triangulation
        var indices: [UInt32] = []
        let vertsPerRow = UInt32(slices + 1)
        for stack in 0..<UInt32(stacks) {
            for slice in 0..<UInt32(slices) {
                let topLeft = stack * vertsPerRow + slice
                let topRight = topLeft + 1
                let bottomLeft = (stack + 1) * vertsPerRow + slice
                let bottomRight = bottomLeft + 1

                // First triangle
                indices.append(topLeft)
                indices.append(bottomLeft)
                indices.append(topRight)

                // Second triangle
                indices.append(topRight)
                indices.append(bottomLeft)
                indices.append(bottomRight)
            }
        }

        var descriptor = MeshDescriptor(name: "hemisphere")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }

    /// Updates the material's base-colour texture on an existing sphere
    /// entity when the panorama bridge publishes a new texture resource.
    static func updateTexture(
        on entity: Entity,
        textureResource: TextureResource
    ) {
        guard var model = entity.components[ModelComponent.self] else { return }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(
            tint: .white,
            texture: .init(textureResource)
        )
        model.materials = [material]
        entity.components.set(model)
    }
}
