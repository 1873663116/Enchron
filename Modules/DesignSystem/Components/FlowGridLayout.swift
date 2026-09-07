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
        let arrangement = Self.arrange(sizes: cache.sizes, width: width, spacing: spacing)
        return CGSize(width: arrangement.usedWidth, height: arrangement.totalHeight)
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
        public var usedWidth: CGFloat
    }

    public static func arrange(sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> Arrangement {
        var origins: [CGPoint] = []
        origins.reserveCapacity(sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return Arrangement(
            origins: origins,
            totalHeight: sizes.isEmpty ? 0 : y + rowHeight,
            usedWidth: usedWidth
        )
    }
}
