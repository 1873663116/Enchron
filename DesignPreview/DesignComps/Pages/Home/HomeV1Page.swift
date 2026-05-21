import SwiftUI

struct HomeV1Page: View {
    var artboardSize: CGSize = Self.defaultArtboardSize

    private static var defaultArtboardSize: CGSize {
        CGSize(
            width: DesignTokens.Card.gridMin * 5 + DesignTokens.Card.gridSpacing * 7,
            height: DesignTokens.Card.gridMin * 3 + DesignTokens.Card.gridSpacing * 3
        )
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            sidebar

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                header
                heroRegion
                contentGrid
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .enchronGlassPanel()
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(width: artboardSize.width, height: artboardSize.height)
        .background(.black.opacity(0.82))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-HomeV1Page")
        .accessibilityLabel("Home V1 page skeleton")
    }

    private var sidebar: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            sidebarItem("house.fill", "Home", isSelected: true)
            sidebarItem("folder.fill", "Files")
            sidebarItem("gearshape.fill", "Settings")
            Spacer()
            sidebarItem("sparkles", "Scene")
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(width: DesignTokens.Interactive.large + DesignTokens.Spacing.lg)
        .enchronGlassMenu()
        .accessibilityIdentifier("DesignComps-HomeV1Page-sidebar")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Home V1")
                    .font(DesignTokens.Typography.title)
                Text("Primary home layout region")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Capsule()
                .fill(DesignTokens.Surface.elevated)
                .frame(width: DesignTokens.Card.gridMin, height: DesignTokens.Interactive.large)
                .overlay {
                    Text("Search / Bridge")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var heroRegion: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            labeledPanel("Hero / Continue Watching")
                .frame(maxWidth: .infinity)
            labeledPanel("Quick Actions")
                .frame(width: DesignTokens.Card.gridMin * 1.4)
        }
        .frame(height: DesignTokens.Card.gridMin * 0.82)
    }

    private var contentGrid: some View {
        HStack(spacing: DesignTokens.Card.gridSpacing) {
            labeledPanel("Recent Files")
            labeledPanel("Scenes")
            labeledPanel("Library Signals")
        }
        .frame(maxHeight: .infinity)
    }

    private func sidebarItem(_ symbol: String, _ label: String, isSelected: Bool = false) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: symbol)
                .font(DesignTokens.SymbolSize.control)
            Text(label)
                .font(DesignTokens.Typography.metadata)
        }
        .foregroundStyle(isSelected ? .white : .secondary)
        .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
        .background(isSelected ? DesignTokens.Surface.selected : .clear, in: Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.automatic)
        .contentShape(Circle())
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
    HomeV1Page()
}
