import DesignSystem
import DeveloperToolsSupport
import PlaybackPresentation
import RealityKit
import SwiftUI
import UIKit

struct WindowPlaybackPreview: View {
    @State private var showsControls = true

    var body: some View {
        WindowPlaybackRootView(
            layout: fixtureLayout,
            preferredInitialSize: fixtureInitialSize,
            showsWindowChrome: showsControls,
            onSurfaceTap: { showsControls.toggle() }
        ) {
            WindowPlaybackRealityFixture()
        } topChrome: {
            WindowPlaybackTopChrome {
                GlassCircleIconButton.back(accessibilityLabel: "Back")
            } spatialActions: {
                WindowPlaybackSpatialActions {
                    GlassCircleIconButton.environment(accessibilityLabel: "Dock")
                } formatControl: {
                    GlassCircleIconButton.expandVertically(
                        accessibilityLabel: "Video Format"
                    )
                }
            } moreControl: {
                GlassCircleIconButton(
                    systemName: "ellipsis",
                    accessibilityLabel: "More"
                )
            }
        } mediaFacts: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("The Weight of Greatness")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.primary)

                Text("4K · HDR · HEVC · Spatial Audio")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
        }
        .ornament(
            visibility: showsControls ? .visible : .hidden,
            attachmentAnchor: .scene(.bottom)
        ) {
            FusedPlayerPanel()
                .accessibilityIdentifier("Preview-window-controls-ornament")
        }
        .onAppear {
            showsControls = true
        }
    }

    private var fixtureLayout: WindowPlaybackLayout {
        WindowPlaybackLayout(
            aspectRatio: WindowPlaybackRealityFixture.imageAspectRatio
        )
    }

    private var fixtureInitialSize: CGSize? {
        guard let rawWidth = ProcessInfo.processInfo.environment[
            "ENCHRON_DESIGN_PREVIEW_WINDOW_WIDTH"
        ],
        let width = Double(rawWidth),
        width.isFinite,
        width > 0 else {
            return nil
        }
        return CGSize(
            width: width,
            height: width / fixtureLayout.aspectRatio
        )
    }
}

private struct WindowPlaybackRealityFixture: View {
    static let imageAspectRatio: CGFloat = {
        guard let image = UIImage(named: "WindowPlaybackDaylightAction"),
              image.size.height > 0 else {
            return WindowPlaybackLayout.fallbackAspectRatio
        }
        return image.size.width / image.size.height
    }()

    @State private var screenEntity = Entity()
    @State private var screenSize =
        WindowPlaybackSurfaceGeometry.defaultSurfaceSize

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                await prepareScreenIfNeeded()
                addScreenIfNeeded(to: content)
                updateScreenLayout(in: content, geometry: geometry)
            } update: { content in
                addScreenIfNeeded(to: content)
                updateScreenLayout(in: content, geometry: geometry)
            }
            .allowsHitTesting(false)
            .frame(depth: WindowPlaybackSurfaceGeometry.flatDepth)
        }
        .frame(depth: WindowPlaybackSurfaceGeometry.flatDepth)
    }

    @MainActor
    private func prepareScreenIfNeeded() async {
        guard screenEntity.components[ModelComponent.self] == nil,
              let image = UIImage(named: "WindowPlaybackDaylightAction"),
              let cgImage = image.cgImage,
              let texture = try? await TextureResource(
                image: cgImage,
                options: .init(semantic: .color)
              ) else {
            return
        }
        let aspectRatio = Float(cgImage.width) / Float(cgImage.height)
        screenSize = [
            aspectRatio,
            WindowPlaybackSurfaceGeometry.unitHeight
        ]
        let material = UnlitMaterial(texture: texture)
        let cornerRadius = Float(
            DesignTokens.Radius.card
                / WindowPlaybackLayout(aspectRatio: Self.imageAspectRatio).defaultSize.height
        )
        screenEntity.components.set(
            ModelComponent(
                mesh: .generatePlane(
                    width: aspectRatio,
                    height: WindowPlaybackSurfaceGeometry.unitHeight,
                    cornerRadius: cornerRadius
                ),
                materials: [material]
            )
        )
        screenEntity.components.set(
            ModelSortGroupComponent(
                group: .planarUIAlwaysBehind,
                order: WindowPlaybackSurfaceGeometry.backgroundSortOrder
            )
        )
        screenEntity.name = "WindowPlaybackPreview.Screen"
    }

    @MainActor
    private func addScreenIfNeeded(to content: RealityViewContent) {
        guard screenEntity.components[ModelComponent.self] != nil,
              content.entities.contains(where: { $0 === screenEntity }) == false else {
            return
        }
        content.add(screenEntity)
    }

    @MainActor
    private func updateScreenLayout(
        in content: RealityViewContent,
        geometry: GeometryProxy3D
    ) {
        guard screenEntity.components[ModelComponent.self] != nil else { return }
        let sceneBounds = content.convert(
            geometry.frame(in: .local),
            from: .local,
            to: .scene
        )
        guard let layout = WindowPlaybackSurfaceGeometry.layout(
            surfaceSize: screenSize,
            sceneCenter: sceneBounds.center,
            sceneExtents: sceneBounds.extents
        ) else {
            return
        }
        screenEntity.position = layout.sceneCenter
        screenEntity.scale = .init(repeating: layout.scale)
    }
}

#Preview(
    "Window Playback",
    windowStyle: .plain
) {
    WindowPlaybackPreview()
} cameras: {
    PreviewCamera(
        from: .front,
        name: "Window Front"
    )
}
