import SwiftUI

struct HomeV1Page: View {
    var body: some View {
        ZStack(alignment: .top) {
            windowPanel
        }
        .padding(DesignTokens.Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-HomeV1Page")
        .accessibilityLabel("Home V1 page")
    }

    private var windowPanel: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                Text("Title")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                Spacer()

                searchField
            }
            .padding(.top, DesignTokens.Spacing.xxl)
            .padding(.horizontal, DesignTokens.Spacing.xxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .enchronGlassWindow()
        .overlay {
            DesignTokens.ShapeToken.panel
                .strokeBorder(
                    DesignTokens.Surface.border,
                    lineWidth: DesignTokens.Stroke.subtle
                )
        }
    }

    private var searchField: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "mic.fill")
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.secondary)

            Text("Search")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(
            width: DesignTokens.Card.gridMin + DesignTokens.Spacing.xxxl * 2,
            height: DesignTokens.Interactive.large
        )
        .background(DesignTokens.Surface.overlay, in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .contentShape(Capsule())
        .accessibilityIdentifier("DesignComps-HomeV1Page-search")
        .accessibilityLabel("Search")
    }
}

#Preview("Home V1", windowStyle: .automatic) {
    HomeV1Page()
        .frame(
            width: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.width,
            height: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.height
        )
}
