import SwiftUI

struct VideoDetailPage: View {
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxl) {
            previewColumn
            detailColumn
        }
        .padding(DesignTokens.Spacing.xxxl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-VideoDetailPage")
        .accessibilityLabel("Video detail page skeleton")
    }

    private var previewColumn: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            videoPreview

            HStack(spacing: DesignTokens.Card.gridSpacing) {
                SceneCardMedium(icon: "rectangle.on.rectangle", title: "Window", isSelected: true)
                SceneCardMedium(icon: "sparkles.tv", title: "Cinema", isSelected: false)
                SceneCardMedium(icon: "mountain.2", title: "Space", isSelected: false)
            }
            .frame(height: DesignTokens.Card.gridMin * 0.64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("DesignComps-VideoDetailPage-previewColumn")
    }

    private var videoPreview: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: DesignTokens.PrecisionTimeline.thumbnailPalette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text("HDR10+")
                    .font(DesignTokens.Typography.badge)
                    .enchronGlassBadge()
                Text("2:49:00")
                    .font(DesignTokens.Typography.badge)
                    .monospacedDigit()
                    .enchronGlassBadge()
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .overlay(alignment: .topLeading) {
            Text("Video Preview")
                .font(DesignTokens.Typography.headline)
                .padding(DesignTokens.Spacing.lg)
        }
        .enchronGlassCard()
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            titleRegion
            metadataRegion
            configurationRegion
            Spacer()
            playEntry
        }
        .frame(width: DesignTokens.Card.gridMin * 2 + DesignTokens.Card.gridSpacing)
        .accessibilityIdentifier("DesignComps-VideoDetailPage-detailColumn")
    }

    private var titleRegion: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Interstellar")
                .font(DesignTokens.Typography.title)
            Text("Modified 2h ago / second-level playback preparation")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var metadataRegion: some View {
        HStack(spacing: DesignTokens.Card.gridSpacing) {
            metadataTile("File Size", "42.8 GB")
            metadataTile("Dynamic Range", "HDR10+")
        }
        .frame(height: DesignTokens.Card.gridMin * 0.48)
    }

    private var configurationRegion: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Playback Settings")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            MenuItemRow(title: "Subtitles", isExpanded: false)
            MenuItemRow(title: "Audio Track", isExpanded: false)

            HStack {
                Text("Auto Resume")
                    .font(DesignTokens.Typography.headline)
                Spacer()
                MockToggle(isOn: true)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.Interactive.rowHeight)
            .enchronGlassMenuItem()
        }
        .padding(DesignTokens.Menu.glassPadding)
        .enchronGlassMenu()
    }

    private var playEntry: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "play.fill")
                .font(DesignTokens.SymbolSize.action)
            Text("Play")
                .font(DesignTokens.Typography.headline)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.ControlBar.paddingH)
        .frame(height: DesignTokens.Interactive.xl)
        .background(DesignTokens.ControlBar.primaryFill, in: Capsule())
        .foregroundStyle(DesignTokens.ControlBar.primarySymbol)
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.lift)
        .contentShape(Capsule())
        .accessibilityIdentifier("DesignComps-VideoDetailPage-playEntry")
        .accessibilityLabel("Play")
    }

    private func metadataTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(DesignTokens.Typography.headline)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .enchronGlassPanel()
    }
}

#Preview(windowStyle: .automatic) {
    DesignCompWindowPreviewStage {
        VideoDetailPage()
    }
}
