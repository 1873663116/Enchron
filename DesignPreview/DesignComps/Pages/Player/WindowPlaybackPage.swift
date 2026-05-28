import SwiftUI
import UIKit

struct WindowPlaybackPage: View {
    static let aspectRatio: CGFloat = 16.0 / 9.0
    static let defaultSize = CGSize(width: 1920, height: 1080)
    static let minimumSize = CGSize(width: 960, height: 540)
    static let maximumSize = CGSize(width: 2880, height: 1620)
    private static let playbackContentShape = DesignTokens.ShapeToken.panel

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            renderSurface
            playbackEdgeShade
            playbackControls
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .frame(
            minWidth: Self.minimumSize.width,
            idealWidth: Self.defaultSize.width,
            maxWidth: Self.maximumSize.width,
            minHeight: Self.minimumSize.height,
            idealHeight: Self.defaultSize.height,
            maxHeight: Self.maximumSize.height
        )
        .clipShape(Self.playbackContentShape)
        .contentShape(Self.playbackContentShape)
        .overlay(alignment: .topLeading) {
            WindowPlaybackResizeConfigurator(
                size: Self.defaultSize,
                minimumSize: Self.minimumSize,
                maximumSize: Self.maximumSize
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-WindowPlaybackPage")
        .accessibilityLabel("Window playback preview")
    }

    private var renderSurface: some View {
        WindowPlaybackRenderSurface(frameImage: WindowPlaybackArtwork.uiImage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
            .accessibilityIdentifier("DesignComps-WindowPlaybackPage-renderSurface")
    }

    private var playbackEdgeShade: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.48), .black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [.clear, .black.opacity(0.26), .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 340)
        }
        .allowsHitTesting(false)
    }

    private var playbackControls: some View {
        VStack {
            topControls
            Spacer(minLength: 0)
            bottomControls
        }
        .padding(DesignTokens.Spacing.xxxl)
    }

    private var topControls: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            Button {
                dismissWindow(id: DesignPreviewNavigationModel.windowPlaybackWindowID)
            } label: {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.white)
                    .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
                    .enchronGlassControl()
            }
            .buttonStyle(.plain)
            .enchronPressFeedback(.icon)
            .clipShape(Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.lift)
            .contentShape(Circle())
            .accessibilityIdentifier("DesignComps-WindowPlaybackPage-back")
            .accessibilityLabel("Close playback window")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Daylight Protocol")
                    .font(DesignTokens.Typography.title)
                    .lineLimit(1)
                Text("00:42:18 / 02:09:40")
                    .font(DesignTokens.Typography.metadata)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.Interactive.large)
            .enchronGlassToolbar()

            Spacer(minLength: 0)

            HStack(spacing: DesignTokens.Spacing.sm) {
                topControlButton("speaker.wave.2", label: "Audio")
                topControlButton("captions.bubble", label: "Subtitles")
                topControlButton("ellipsis", label: "More")
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PlayerProgressStrip()
            PlayerControlBar()
        }
        .frame(maxWidth: .infinity)
    }

    private func topControlButton(_ systemName: String, label: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.white)
                .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
                .enchronGlassControl()
        }
        .buttonStyle(.plain)
        .enchronPressFeedback(.icon)
        .clipShape(Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignComps-WindowPlaybackPage-\(label)")
        .accessibilityLabel(label)
    }
}

// DesignComp stand-in for the production WindowVideoView CAMetalLayer / MTKView surface.
private struct WindowPlaybackRenderSurface: UIViewRepresentable {
    let frameImage: UIImage?

    func makeUIView(context: Context) -> RenderSurfaceView {
        let view = RenderSurfaceView()
        view.update(frameImage: frameImage)
        return view
    }

    func updateUIView(_ view: RenderSurfaceView, context: Context) {
        view.update(frameImage: frameImage)
    }

    final class RenderSurfaceView: UIView {
        private let imageView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isOpaque = false
            isUserInteractionEnabled = false
            clipsToBounds = true
            layer.masksToBounds = true

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.backgroundColor = .clear
            imageView.isOpaque = false
            imageView.isUserInteractionEnabled = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
                imageView.topAnchor.constraint(equalTo: topAnchor),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func update(frameImage: UIImage?) {
            imageView.image = frameImage
        }
    }
}

private struct WindowPlaybackResizeConfigurator: UIViewControllerRepresentable {
    let size: CGSize
    let minimumSize: CGSize
    let maximumSize: CGSize

    func makeUIViewController(context: Context) -> Controller {
        Controller(size: size, minimumSize: minimumSize, maximumSize: maximumSize)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(size: size, minimumSize: minimumSize, maximumSize: maximumSize)
    }

    @MainActor
    final class Controller: UIViewController {
        private var size: CGSize
        private var minimumSize: CGSize
        private var maximumSize: CGSize
        private var didApplyGeometryPreferences = false

        init(size: CGSize, minimumSize: CGSize, maximumSize: CGSize) {
            self.size = size
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
            view.isOpaque = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyGeometryPreferencesIfNeeded()
        }

        func update(size: CGSize, minimumSize: CGSize, maximumSize: CGSize) {
            self.size = size
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
            didApplyGeometryPreferences = false
            applyGeometryPreferencesIfNeeded()
        }

        private func applyGeometryPreferencesIfNeeded() {
            guard !didApplyGeometryPreferences,
                  let windowScene = view.window?.windowScene
            else {
                return
            }

            didApplyGeometryPreferences = true
            let preferences = UIWindowScene.GeometryPreferences.Vision(
                size: size,
                minimumSize: minimumSize,
                maximumSize: maximumSize,
                resizingRestrictions: .uniform
            )
            windowScene.requestGeometryUpdate(preferences) { error in
                print("DesignPreview playback window geometry request failed: \(error.localizedDescription)")
            }
        }
    }
}

private enum WindowPlaybackArtwork {
    private static let assetName = "WindowPlaybackDaylightAction"
    // Canvas can preview before the asset catalog refreshes; keep the bundle asset as the primary path.
    private static let localFallbackPath =
        "/Users/xiongzhipeng/Applications/Enchron/DesignPreview/Assets.xcassets/WindowPlaybackDaylightAction.imageset/window-playback-daylight-action.png"

    static var uiImage: UIImage? {
        UIImage(named: assetName) ?? UIImage(contentsOfFile: localFallbackPath)
    }
}

#Preview("Window Playback", windowStyle: .plain, traits: .fixedLayout(width: 1920, height: 1080)) {
    WindowPlaybackPage()
}
