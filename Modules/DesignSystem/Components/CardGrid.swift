import SwiftUI

public struct CardGrid<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        FlowGridLayout(spacing: DesignTokens.Card.gridSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.artworkLoadsWhenVisible, true)
    }
}
