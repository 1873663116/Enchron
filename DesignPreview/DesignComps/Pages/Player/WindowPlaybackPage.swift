import SwiftUI
import UIKit

struct WindowPlaybackPage: View {
    static let aspectRatio = CGSize(width: 16, height: 9)
    static let minimumContentSize = CGSize(width: 960, height: 540)
    static let idealContentSize = CGSize(width: 1280, height: 720)
    static let maximumContentSize = CGSize(width: 1600, height: 900)

    private static let designContentSize = idealContentSize

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isChromeVisible = false
    @State private var progressTimelineResetToken = 0

    var body: some View {
        scaledPlaybackBoundary
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(
                minWidth: Self.minimumContentSize.width,
                idealWidth: Self.idealContentSize.width,
                maxWidth: Self.maximumContentSize.width,
                minHeight: Self.minimumContentSize.height,
                idealHeight: Self.idealContentSize.height,
                maxHeight: Self.maximumContentSize.height
            )
            .frame(depth: 1)
            .background {
                WindowPlaybackSceneResizePreference(
                    idealSize: Self.idealContentSize,
                    minimumSize: Self.minimumContentSize,
                    maximumSize: Self.maximumContentSize
                )
                .allowsHitTesting(false)
            }
            .contentShape(.interaction, playbackShape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("DesignComps-WindowPlaybackPage")
            .accessibilityLabel("Window playback preview")
    }

    private var scaledPlaybackBoundary: some View {
        GeometryReader { proxy in
            let scale = Self.scale(for: proxy.size)

            playbackBoundary
                .frame(width: Self.designContentSize.width, height: Self.designContentSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var playbackBoundary: some View {
        ZStack {
            renderSurface
            chromeToggleTarget
            playbackChrome
                .opacity(isChromeVisible ? 1 : 0)
                .allowsHitTesting(isChromeVisible)
                .animation(DesignTokens.AnimationToken.controlsTransition, value: isChromeVisible)
        }
        .clipShape(playbackShape)
    }

    private var chromeToggleTarget: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleChromeVisibility)
            .accessibilityHidden(true)
    }

    private var playbackChrome: some View {
        ZStack {
            controlMask
            VStack {
                topControls
                    .padding(DesignTokens.Spacing.xl)

                Spacer(minLength: 0)

                bottomControls
                    .padding(.horizontal, DesignTokens.Spacing.xxl)
                    .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
    }

    private var renderSurface: some View {
        WindowPlaybackFixtureSurface()
            .accessibilityHidden(true)
            .accessibilityIdentifier("DesignComps-WindowPlaybackPage-renderSurface")
    }

    private var controlMask: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        .black.opacity(0.40),
                        .black.opacity(0.18),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * topMaskHeightRatio)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.22),
                        .black.opacity(0.44)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * bottomMaskHeightRatio)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topControls: some View {
        HStack {
            GlassCircleIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Close playback window",
                action: {
                    dismissWindow(id: DesignPreviewNavigationModel.windowPlaybackWindowID)
                },
                accessibilityIdentifier: "DesignComps-WindowPlaybackPage-back"
            )

            Spacer(minLength: 0)

            GlassCircleIconButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "Expand playback window",
                accessibilityIdentifier: "DesignComps-WindowPlaybackPage-expand"
            )
        }
    }

    private var bottomControls: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PlayerProgressStrip(timelineResetToken: progressTimelineResetToken)
            PlayerControlBar()
        }
        .frame(maxWidth: .infinity)
    }

    private var topMaskHeightRatio: CGFloat { 0.30 }
    private var bottomMaskHeightRatio: CGFloat { 0.36 }
    private var playbackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
    }

    private static func scale(for size: CGSize) -> CGFloat {
        min(size.width / designContentSize.width, size.height / designContentSize.height)
    }

    private func toggleChromeVisibility() {
        withAnimation(DesignTokens.AnimationToken.controlsTransition) {
            if isChromeVisible {
                progressTimelineResetToken += 1
            }
            isChromeVisible.toggle()
        }
    }
}

private struct WindowPlaybackFixtureSurface: View {
    private static let fixtureAssetName = "WindowPlaybackDaylightAction"

    var body: some View {
        GeometryReader { proxy in
            Color.black
                .overlay {
                    Image(Self.fixtureAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
        }
    }
}

private struct WindowPlaybackSceneResizePreference: UIViewControllerRepresentable {
    let idealSize: CGSize
    let minimumSize: CGSize
    let maximumSize: CGSize

    func makeUIViewController(context: Context) -> ResizePreferenceController {
        ResizePreferenceController(
            idealSize: idealSize,
            minimumSize: minimumSize,
            maximumSize: maximumSize
        )
    }

    func updateUIViewController(_ controller: ResizePreferenceController, context: Context) {
        controller.update(
            idealSize: idealSize,
            minimumSize: minimumSize,
            maximumSize: maximumSize
        )
    }

    final class ResizePreferenceController: UIViewController {
        private var idealSize: CGSize
        private var minimumSize: CGSize
        private var maximumSize: CGSize
        private var appliedSignature: ResizePreferenceSignature?

        init(idealSize: CGSize, minimumSize: CGSize, maximumSize: CGSize) {
            self.idealSize = idealSize
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPreferenceIfPossible()
        }

        func update(idealSize: CGSize, minimumSize: CGSize, maximumSize: CGSize) {
            self.idealSize = idealSize
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
            applyPreferenceIfPossible()
        }

        private func applyPreferenceIfPossible() {
            guard let windowScene = view.window?.windowScene else { return }

            let signature = ResizePreferenceSignature(
                idealSize: idealSize,
                minimumSize: minimumSize,
                maximumSize: maximumSize
            )
            guard appliedSignature != signature else { return }
            appliedSignature = signature

            windowScene.requestGeometryUpdate(
                .Vision(
                    size: idealSize,
                    minimumSize: minimumSize,
                    maximumSize: maximumSize,
                    resizingRestrictions: .uniform
                )
            )
        }
    }

    private struct ResizePreferenceSignature: Equatable {
        let idealSize: CGSize
        let minimumSize: CGSize
        let maximumSize: CGSize
    }
}

#Preview("Window Playback", windowStyle: .plain) {
    WindowPlaybackPage()
}
