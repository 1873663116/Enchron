import DesignSystem
import SwiftUI

public struct EmbyShelf<Content: View>: View {
    private let title: String?
    private let inset: CGFloat
    private let content: Content

    public init(
        title: String?,
        inset: CGFloat = DesignTokens.Spacing.xxl,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.inset = inset
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if let title {
                Text(title)
                    .font(DesignTokens.Typography.title)
                    .padding(.horizontal, inset)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                    content
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Shelf")
    }
}
