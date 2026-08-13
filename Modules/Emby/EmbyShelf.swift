import DesignSystem
import SwiftUI

/// One horizontally scrolling row of cards. The episode row carries its season control instead of
/// a title, so the title is optional.
public struct EmbyShelf<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(
        title: String?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if let title {
                Text(title)
                    .font(DesignTokens.Typography.title)
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                    content
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title ?? "Shelf")
    }
}
