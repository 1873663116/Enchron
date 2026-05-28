import SwiftUI

struct WindowPlaybackPage: View {
    static let aspectRatio = CGSize(width: 16, height: 9)

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isChromeVisible = false

    var body: some View {
        Button(action: toggleChromeVisibility) {
            playbackBoundary
                .aspectRatio(Self.aspectRatio, contentMode: .fit)
                .frame(depth: 1)
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, playbackShape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-WindowPlaybackPage")
        .accessibilityLabel("Window playback preview")
    }

    private var playbackBoundary: some View {
        ZStack {
            renderSurface
            playbackChrome
                .opacity(isChromeVisible ? 1 : 0)
                .allowsHitTesting(false)
                .animation(DesignTokens.AnimationToken.controlsTransition, value: isChromeVisible)
        }
        .clipShape(playbackShape)
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
                        .black.opacity(0.58),
                        .black.opacity(0.30),
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
                        .black.opacity(0.34),
                        .black.opacity(0.62)
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

            GlassCapsuleIconLabelButton(
                title: "Expand",
                systemName: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "Expand playback window",
                accessibilityIdentifier: "DesignComps-WindowPlaybackPage-expand"
            )
        }
    }

    private var bottomControls: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PlayerProgressStrip()
            PlayerControlBar()
        }
        .frame(maxWidth: .infinity)
    }

    private var topMaskHeightRatio: CGFloat { 0.2 }
    private var bottomMaskHeightRatio: CGFloat { 0.26 }
    private var playbackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
    }

    private func toggleChromeVisibility() {
        withAnimation(DesignTokens.AnimationToken.controlsTransition) {
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

#Preview("Window Playback", windowStyle: .plain) {
    WindowPlaybackPage()
}
