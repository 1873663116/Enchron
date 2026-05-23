import SwiftUI

struct EmptyPanelWindowContent<Content: View>: View {
    static var defaultArtboardSize: CGSize {
        CGSize(width: 1920, height: 1080)
    }

    var showsReviewLabel = true
    private let content: Content

    init(
        showsReviewLabel: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.showsReviewLabel = showsReviewLabel
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsReviewLabel {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Empty Panel")
                        .font(DesignTokens.Typography.title)
                    Text("System WindowGroup shell")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.xxxl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-EmptyPanelWindowContent")
        .accessibilityLabel("Empty panel window content")
    }
}

extension EmptyPanelWindowContent where Content == EmptyView {
    init(showsReviewLabel: Bool = true) {
        self.init(showsReviewLabel: showsReviewLabel) {
            EmptyView()
        }
    }
}

struct DesignCompWindowPreviewStage<Content: View>: View {
    var showsSidebar = false
    var sidebarSelection: DesignCompSidebarItem = .files
    private let content: Content

    init(
        showsSidebar: Bool = false,
        sidebarSelection: DesignCompSidebarItem = .files,
        @ViewBuilder content: () -> Content
    ) {
        self.showsSidebar = showsSidebar
        self.sidebarSelection = sidebarSelection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            if showsSidebar {
                DesignCompSidebar(selection: sidebarSelection)
            }

            EmptyPanelWindowContent(showsReviewLabel: false) {
                content
            }
            .frame(
                width: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.width,
                height: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.height
            )
        }
        .padding(DesignTokens.Spacing.xxxl)
    }
}

enum DesignCompSidebarItem {
    case files
    case settings
    case scene
}

struct DesignCompSidebar: View {
    let selection: DesignCompSidebarItem

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            sidebarButton("folder.fill", label: "Files", item: .files)
            sidebarButton("gearshape.fill", label: "Settings", item: .settings)
            Spacer(minLength: DesignTokens.Spacing.xl)
            sidebarButton("mountain.2", label: "Scene", item: .scene)
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(width: DesignTokens.Interactive.large + DesignTokens.Spacing.sm)
        .enchronGlassMenu()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-windowSidebar")
        .accessibilityLabel("Window sidebar")
    }

    private func sidebarButton(
        _ systemName: String,
        label: String,
        item: DesignCompSidebarItem
    ) -> some View {
        let isSelected = selection == item

        return Image(systemName: systemName)
            .font(DesignTokens.SymbolSize.control)
            .foregroundStyle(isSelected ? DesignTokens.Theme.accent : .secondary)
            .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
            .background(isSelected ? DesignTokens.Surface.selected : .clear, in: Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.automatic)
            .contentShape(Circle())
            .accessibilityLabel(label)
    }
}
