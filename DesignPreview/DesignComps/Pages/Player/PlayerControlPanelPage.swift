import SwiftUI

struct PlayerControlPanelPage: View {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-PlayerControlPanelPage")
        .accessibilityLabel("Player control panel page skeleton")
    }

    private var topControlRegion: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
            circleControl("chevron.left", label: "Back")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Title")
                    .font(DesignTokens.Typography.title)
                Text("Playback Context")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.Interactive.large)
            .enchronGlassToolbar()

            Spacer()

            HStack(spacing: DesignTokens.Spacing.sm) {
                circleControl("rectangle.on.rectangle", label: "Window")
                circleControl("ellipsis", label: "More")
            }
        }
    }

    private var bottomControlRegion: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PlayerProgressStrip()
            PlayerControlBar()

            Text("Player Control Panel / base state")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func circleControl(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(DesignTokens.SymbolSize.control)
            .foregroundStyle(.white)
            .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
            .enchronGlassControl()
            .accessibilityLabel(label)
    }
}

private struct PlayerPreviewVideoSurface: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    .black,
                    DesignTokens.PrecisionTimeline.thumbnailPalette[0].opacity(0.72),
                    DesignTokens.PrecisionTimeline.thumbnailPalette[2].opacity(0.64),
                    .black.opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Video Surface")
                    .font(DesignTokens.Typography.title)
                Text("Window content behind player controls")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.xxxl)
        }
    }
}

#Preview(windowStyle: .automatic) {
    DesignCompWindowPreviewStage {
        PlayerControlPanelPage()
    }
}
