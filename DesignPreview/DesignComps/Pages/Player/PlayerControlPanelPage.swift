import SwiftUI

struct PlayerControlPanelPage: View {
    var artboardSize: CGSize = Self.defaultArtboardSize

    private static var defaultArtboardSize: CGSize {
        CGSize(
            width: DesignTokens.Layout.playerControlsWidth * 2,
            height: DesignTokens.Layout.playerControlsWidth * 0.72
        )
    }

    var body: some View {
        ZStack {
            PlayerPreviewVideoSurface()

            VStack {
                topControlRegion
                Spacer()
                bottomControlRegion
            }
            .padding(DesignTokens.Spacing.xxxl)
        }
        .frame(width: artboardSize.width, height: artboardSize.height)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-PlayerControlPanelPage")
        .accessibilityLabel("Player control panel page skeleton")
    }

    private var topControlRegion: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
            Circle()
                .fill(DesignTokens.Surface.overlay)
                .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
                .overlay {
                    Image(systemName: "chevron.left")
                        .font(DesignTokens.SymbolSize.control)
                        .foregroundStyle(.white)
                }
                .enchronGlassControl()

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Title / Playback Context")
                    .font(DesignTokens.Typography.headline)
                Text("Top control region")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.Interactive.large)
            .enchronGlassToolbar()

            Spacer()

            HStack(spacing: DesignTokens.Spacing.sm) {
                controlPlaceholder("square.dashed")
                controlPlaceholder("ellipsis")
            }
        }
    }

    private var bottomControlRegion: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PlayerProgressStrip()

            HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                labeledControl("gobackward.10", "Back")
                labeledControl("play.fill", "Primary")
                    .frame(width: DesignTokens.Interactive.xl, height: DesignTokens.Interactive.xl)
                labeledControl("goforward.10", "Forward")
            }
            .padding(.horizontal, DesignTokens.ControlBar.paddingH)
            .padding(.vertical, DesignTokens.ControlBar.paddingV)
            .frame(width: DesignTokens.ControlBar.width)
            .enchronGlassControl()

            Text("Bottom progress / transport region")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func controlPlaceholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(DesignTokens.SymbolSize.control)
            .foregroundStyle(.white)
            .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
            .enchronGlassControl()
    }

    private func labeledControl(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: symbol)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.white)
            Text(label)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
    }
}

private struct PlayerPreviewVideoSurface: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    .black,
                    DesignTokens.Theme.accent.opacity(0.18),
                    .black.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Video Surface")
                    .font(DesignTokens.Typography.title)
                Text("Player background / content area")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.xxxl)
        }
    }
}

#Preview(windowStyle: .automatic) {
    PlayerControlPanelPage()
}
