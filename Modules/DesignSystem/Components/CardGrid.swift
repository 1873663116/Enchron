import SwiftUI

private struct CardColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

public extension EnvironmentValues {
    var cardColumnWidth: CGFloat? {
        get { self[CardColumnWidthKey.self] }
        set { self[CardColumnWidthKey.self] = newValue }
    }
}

public struct CardGrid<Content: View>: View {
    private let minimumCardWidth: CGFloat
    private let content: Content

    @State private var containerWidth: CGFloat?

    public init(
        minimumCardWidth: CGFloat = DesignTokens.Card.gridMin,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumCardWidth = minimumCardWidth
        self.content = content()
    }

    public var body: some View {
        FlowGridLayout(spacing: DesignTokens.Card.gridSpacing) {
            content
        }
        .environment(\.cardColumnWidth, columnWidth)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            containerWidth = $0
        }
        .environment(\.artworkLoadsWhenVisible, true)
    }

    private var columnWidth: CGFloat? {
        guard let containerWidth, containerWidth > 0 else { return nil }
        return Self.columnWidth(
            filling: containerWidth,
            minimumCardWidth: minimumCardWidth,
            spacing: DesignTokens.Card.gridSpacing
        )
    }

    public static func columnWidth(
        filling width: CGFloat,
        minimumCardWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard minimumCardWidth > 0 else { return width }
        let columns = max(Int(((width + spacing) / (minimumCardWidth + spacing)).rounded(.down)), 1)
        let filled = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return max(filled, minimumCardWidth)
    }
}
