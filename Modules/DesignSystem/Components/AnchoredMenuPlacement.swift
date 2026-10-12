import Foundation
import SwiftUI

public enum AnchoredMenuSizing: Equatable {
    case content
    case grid(itemCount: Int)
    case fixed(width: CGFloat)

    public func width(idealContentWidth: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let padding = DesignTokens.Menu.glassPadding * 2
        let requested: CGFloat
        switch self {
        case .content:
            requested = min(max(idealContentWidth + padding, DesignTokens.Menu.minimumWidth),
                            DesignTokens.Menu.maximumWidth)
        case let .grid(itemCount):
            let columns = min(max(itemCount, DesignTokens.Menu.minimumGridColumns),
                              DesignTokens.Menu.maximumGridColumns)
            requested = CGFloat(columns) * DesignTokens.Interactive.large + padding
        case let .fixed(width):
            requested = width
        }
        return max(0, min(requested, availableWidth))
    }

    public func height(contentHeight: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let requested = max(DesignTokens.Menu.minimumHeight,
                            contentHeight + DesignTokens.Menu.glassPadding * 2)
        let limit: CGFloat
        switch self {
        case .content, .grid:
            limit = DesignTokens.Menu.maximumContentHeight
        case .fixed:
            limit = availableHeight
        }
        return max(0, min(requested, limit, availableHeight))
    }
}

public struct AnchoredMenuContainerShape: RoundedRectangularShape {
    public let radius: CGFloat
    private var inset: CGFloat = 0

    init(radius: CGFloat) { self.radius = radius }

    public func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .inset(by: inset)
            .path(in: rect)
    }

    public func corners(in size: CGSize?) -> RoundedRectangularShapeCorners? {
        let maximum = size.map { min($0.width, $0.height) / 2 } ?? radius
        return .fixed(max(0, min(radius, maximum) - inset))
    }

    public func inset(by amount: CGFloat) -> Self {
        var shape = self
        shape.inset += amount
        return shape
    }
}

public struct AnchoredMenuPlacement: Equatable {
    public enum Edge: CaseIterable, Sendable {
        case above, below, leading, trailing
    }

    public let frame: CGRect
    public let source: CGRect
    public let edge: Edge
    public let boundary: CGFloat

    public static func root(
        source: CGRect,
        size: CGSize,
        bounds: CGRect,
        preferredEdge: Edge
    ) -> Self {
        let gap = DesignTokens.Menu.sourceGap
        let edges = [preferredEdge] + Edge.allCases.filter { $0 != preferredEdge }
        var best = adjacent(source: source, size: size, bounds: bounds, edge: preferredEdge, gap: gap)
        for edge in edges {
            let candidate = adjacent(source: source, size: size, bounds: bounds, edge: edge, gap: gap)
            if bounds.contains(candidate.frame) { return candidate }
            if candidate.frame.intersection(bounds).area > best.frame.intersection(bounds).area {
                best = candidate
            }
        }
        return best
    }

    public static func submenu(source: CGRect, parent: CGRect, size: CGSize, bounds: CGRect) -> Self {
        let overlap = DesignTokens.Menu.submenuOverlap
        let leadingRoom = parent.minX - bounds.minX + overlap
        let trailingRoom = bounds.maxX - parent.maxX + overlap
        let edge: Edge = trailingRoom >= size.width || trailingRoom >= leadingRoom ? .trailing : .leading
        let boundary = edge == .leading ? parent.minX + overlap : parent.maxX - overlap
        let bottom = size.height > parent.height ? min(parent.maxY, bounds.maxY) : bounds.maxY
        let origin = CGPoint(
            x: edge == .leading ? boundary - size.width : boundary,
            y: clamp(source.midY - size.height / 2, lower: bounds.minY, upper: bottom - size.height)
        )
        return Self(frame: CGRect(origin: origin, size: size), source: source, edge: edge, boundary: boundary)
    }

    public func frame(at progress: CGFloat) -> CGRect {
        let scale = max(0, DesignTokens.AnimationToken.menuInitialScale
            + (1 - DesignTokens.AnimationToken.menuInitialScale) * progress)
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        let fraction = max(0, progress)
        var center = CGPoint(
            x: source.midX + (frame.midX - source.midX) * fraction,
            y: source.midY + (frame.midY - source.midY) * fraction
        )
        switch edge {
        case .above: center.y = boundary - size.height / 2
        case .below: center.y = boundary + size.height / 2
        case .leading: center.x = boundary - size.width / 2
        case .trailing: center.x = boundary + size.width / 2
        }
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    private static func adjacent(
        source: CGRect, size: CGSize, bounds: CGRect, edge: Edge, gap: CGFloat
    ) -> Self {
        var origin = CGPoint(
            x: clamp(source.midX - size.width / 2, lower: bounds.minX, upper: bounds.maxX - size.width),
            y: clamp(source.midY - size.height / 2, lower: bounds.minY, upper: bounds.maxY - size.height)
        )
        let boundary: CGFloat
        switch edge {
        case .above:
            boundary = source.minY - gap
            origin.y = boundary - size.height
        case .below:
            boundary = source.maxY + gap
            origin.y = boundary
        case .leading:
            boundary = source.minX - gap
            origin.x = boundary - size.width
        case .trailing:
            boundary = source.maxX + gap
            origin.x = boundary
        }
        return Self(frame: CGRect(origin: origin, size: size), source: source, edge: edge, boundary: boundary)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
