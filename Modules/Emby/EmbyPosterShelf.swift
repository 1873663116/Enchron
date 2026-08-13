import DesignSystem
import SwiftUI

public struct EmbyPosterShelf<Content: View>: View {
    private let title: String
    private let content: Content

    public init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(title)
                .font(DesignTokens.Typography.title)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                    content
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
