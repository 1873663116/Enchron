import SwiftUI
import RealityKit
import Spatial
import UIKit

struct SenseZoneVolumeRoot: View {
    @Environment(DesignPreviewNavigationModel.self) private var navigationModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        CampScenePage(onReturn: returnToMainWindow)
            .overlay {
                SenseZoneVolumeLayoutBoundsProbe()
            }
            .accessibilityIdentifier("DesignComps-SenseZoneVolumeRoot")
            .accessibilityLabel("SenseZone volume")
    }

    private func returnToMainWindow() {
        guard !navigationModel.isSceneTransitionInFlight else { return }

        navigationModel.isSceneTransitionInFlight = true
        navigationModel.restoreReturnRoute()
        openWindow(id: DesignPreviewNavigationModel.mainWindowID)
        dismissWindow(id: DesignPreviewNavigationModel.senseZoneVolumeID)
        navigationModel.isSceneTransitionInFlight = false
    }
}

private struct SenseZoneVolumeLayoutBoundsProbe: View {
    @State private var root = Entity()
    @State private var layoutFrame: Rect3D?

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                // EXPLORATORY: temporary GeometryReader3D bounds probe for volume debugging.
                content.add(root)
            } update: { content in
                let frame = layoutFrame ?? geometry.frame(in: .local)
                let bounds = content.convert(frame, from: .local, to: .scene)

                SenseZoneVolumeBoundsProbeEntity.update(
                    root,
                    width: Float(bounds.extents.x),
                    height: Float(bounds.extents.y),
                    depth: Float(bounds.extents.z)
                )
            }
        }
        .onGeometryChange3D(for: Rect3D.self) { geometry in
            geometry.frame(in: .local)
        } action: { newFrame in
            layoutFrame = newFrame
        }
        .allowsHitTesting(false)
    }
}

private enum SenseZoneVolumeBoundsProbeEntity {
    static func update(
        _ root: Entity,
        width: Float,
        height: Float,
        depth: Float
    ) {
        guard width > 0, height > 0, depth > 0 else { return }

        for child in root.children {
            child.removeFromParent()
        }

        let faceMaterial = SimpleMaterial(
            color: UIColor.cyan.withAlphaComponent(0.08),
            roughness: 0.85,
            isMetallic: false
        )
        let edgeMaterial = SimpleMaterial(
            color: UIColor.cyan.withAlphaComponent(0.92),
            roughness: 0.4,
            isMetallic: false
        )
        let cornerMaterial = SimpleMaterial(
            color: UIColor.white.withAlphaComponent(0.95),
            roughness: 0.35,
            isMetallic: false
        )

        let thickness: Float = 0.006

        addShell(
            to: root,
            width: width,
            height: height,
            depth: depth,
            material: faceMaterial
        )
        addEdgeBars(
            to: root,
            width: width,
            height: height,
            depth: depth,
            thickness: thickness,
            material: edgeMaterial
        )
        addCornerDots(
            to: root,
            width: width,
            height: height,
            depth: depth,
            radius: thickness * 1.45,
            material: cornerMaterial
        )
    }

    private static func addShell(
        to root: Entity,
        width: Float,
        height: Float,
        depth: Float,
        material: SimpleMaterial
    ) {
        root.addChild(edge(size: [width, height, depth], position: [0, 0, 0], material: material))
    }

    private static func addEdgeBars(
        to root: Entity,
        width: Float,
        height: Float,
        depth: Float,
        thickness: Float,
        material: SimpleMaterial
    ) {
        let halfWidth = width / 2
        let halfHeight = height / 2
        let halfDepth = depth / 2

        for y in [-halfHeight, halfHeight] {
            for z in [-halfDepth, halfDepth] {
                root.addChild(
                    edge(
                        size: [width, thickness, thickness],
                        position: [0, y, z],
                        material: material
                    )
                )
            }
        }

        for x in [-halfWidth, halfWidth] {
            for z in [-halfDepth, halfDepth] {
                root.addChild(
                    edge(
                        size: [thickness, height, thickness],
                        position: [x, 0, z],
                        material: material
                    )
                )
            }
        }

        for x in [-halfWidth, halfWidth] {
            for y in [-halfHeight, halfHeight] {
                root.addChild(
                    edge(
                        size: [thickness, thickness, depth],
                        position: [x, y, 0],
                        material: material
                    )
                )
            }
        }
    }

    private static func addCornerDots(
        to root: Entity,
        width: Float,
        height: Float,
        depth: Float,
        radius: Float,
        material: SimpleMaterial
    ) {
        let halfWidth = width / 2
        let halfHeight = height / 2
        let halfDepth = depth / 2

        for x in [-halfWidth, halfWidth] {
            for y in [-halfHeight, halfHeight] {
                for z in [-halfDepth, halfDepth] {
                    let entity = ModelEntity(
                        mesh: .generateSphere(radius: radius),
                        materials: [material]
                    )
                    entity.position = [x, y, z]
                    root.addChild(entity)
                }
            }
        }
    }

    private static func edge(
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        material: SimpleMaterial
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size),
            materials: [material]
        )
        entity.position = position
        return entity
    }
}
