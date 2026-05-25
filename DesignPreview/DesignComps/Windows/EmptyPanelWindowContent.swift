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
    private let content: Content

    init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    var body: some View {
        EmptyPanelWindowContent(showsReviewLabel: false) {
            content
        }
        .frame(
            width: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.width,
            height: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.height
        )
        .padding(DesignTokens.Spacing.xxxl)
    }
}
