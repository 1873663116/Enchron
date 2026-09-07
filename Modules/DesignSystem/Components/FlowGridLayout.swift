import SwiftUI

public struct FlowGridLayout: Layout {
    public struct Cache {
        var sizes: [CGSize] = []
    }

    private let spacing: CGFloat

    public init(spacing: CGFloat) {
        self.spacing = spacing
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = proposal.width ?? cache.sizes.map(\.width).max() ?? 0
        return CGSize(
            width: width,
            height: Self.arrange(sizes: cache.sizes, width: width, spacing: spacing).totalHeight
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let arrangement = Self.arrange(sizes: cache.sizes, width: bounds.width, spacing: spacing)
        for (index, origin) in arrangement.origins.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(cache.sizes[index])
            )
        }
    }

    public struct Arrangement: Equatable {
        public var origins: [CGPoint]
        public var totalHeight: CGFloat
    }

    public static func arrange(sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> Arrangement {
        var origins: [CGPoint] = []
        origins.reserveCapacity(sizes.count)
        let cardWidth = sizes.map(\.width).max() ?? 0
        let columns = Self.columns(fitting: width, cardWidth: cardWidth, spacing: spacing)
        let pitch = cardWidth + Self.justifiedSpacing(
            width: width,
            cardWidth: cardWidth,
            columns: columns,
            spacing: spacing
        )
        var column = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for size in sizes {
            if column == columns {
                column = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: CGFloat(column) * pitch, y: y))
            column += 1
            rowHeight = max(rowHeight, size.height)
        }
        return Arrangement(origins: origins, totalHeight: sizes.isEmpty ? 0 : y + rowHeight)
    }

    static func columns(fitting width: CGFloat, cardWidth: CGFloat, spacing: CGFloat) -> Int {
        guard cardWidth > 0 else { return 1 }
        return max(Int(((width + spacing) / (cardWidth + spacing)).rounded(.down)), 1)
    }

    static func justifiedSpacing(
        width: CGFloat,
        cardWidth: CGFloat,
        columns: Int,
        spacing: CGFloat
    ) -> CGFloat {
        guard columns > 1 else { return spacing }
        return max((width - CGFloat(columns) * cardWidth) / CGFloat(columns - 1), spacing)
    }
}
