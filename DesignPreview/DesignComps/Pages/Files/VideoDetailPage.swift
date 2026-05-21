import SwiftUI

struct VideoDetailPage: View {
    var artboardSize: CGSize = Self.defaultArtboardSize

    private static var defaultArtboardSize: CGSize {
        CGSize(
            width: DesignTokens.Card.gridMin * 5 + DesignTokens.Card.gridSpacing * 7,
            height: DesignTokens.Card.gridMin * 3 + DesignTokens.Card.gridSpacing * 3
        )
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            previewColumn
            detailColumn
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(width: artboardSize.width, height: artboardSize.height)
        .background(.black.opacity(0.82))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-VideoDetailPage")
        .accessibilityLabel("Video detail page skeleton")
    }

    private var previewColumn: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            labeledPanel("Video Preview / Poster")
                .frame(maxHeight: .infinity)

            HStack(spacing: DesignTokens.Spacing.md) {
                labeledPill("Scene")
                labeledPill("Immersive")
                labeledPill("Window")
            }
            .frame(height: DesignTokens.Interactive.large)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .enchronGlassPanel()
        .accessibilityIdentifier("DesignComps-VideoDetailPage-previewColumn")
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            titleRegion

            HStack(spacing: DesignTokens.Spacing.md) {
                metadataBlock("Metadata")
                metadataBlock("HDR / Codec")
            }
            .frame(height: DesignTokens.Card.gridMin * 0.72)

            configurationRegion

            Spacer()

            playEntry
        }
        .frame(width: DesignTokens.Card.gridMin * 2)
        .padding(DesignTokens.Spacing.xl)
        .enchronGlassPanel()
        .accessibilityIdentifier("DesignComps-VideoDetailPage-detailColumn")
    }

    private var titleRegion: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Video Detail Page")
                .font(DesignTokens.Typography.title)
            Text("Second-level playback preparation page")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private var configurationRegion: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Playback Configuration")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            configRow("Subtitles", "Selection region")
            configRow("Audio Track", "Selection region")
            configRow("Scene", "Environment region")
        }
    }

    private var playEntry: some View {
        HStack {
            Image(systemName: "play.fill")
                .font(DesignTokens.SymbolSize.action)
            Text("Play Entry")
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
    }

    private func metadataBlock(_ title: String) -> some View {
        labeledPanel(title)
            .frame(maxWidth: .infinity)
    }

    private func configRow(_ title: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                Text(detail)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
    }

    private func labeledPill(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.Typography.metadata)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .enchronGlassPill()
    }

    private func labeledPanel(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
            .fill(DesignTokens.Surface.elevated)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                    .padding(DesignTokens.Spacing.lg)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.subtle)
            }
    }
}

#Preview(windowStyle: .automatic) {
    VideoDetailPage()
}
