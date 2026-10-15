import SwiftUI

public struct ExpandingControls<Primary: View, Secondary: View, Trailing: View>: View {
    private let primary: Primary
    private let secondary: Secondary
    private let trailing: Trailing

    public init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary, @ViewBuilder trailing: () -> Trailing) {
        self.primary = primary()
        self.secondary = secondary()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: DesignTokens.EnvironmentHome.controlsSpacing) {
            secondary
            primary
            trailing
        }
        .padding(DesignTokens.EnvironmentHome.controlsPadding)
        .enchronWindowGlassBackground(.always)
        .hoverEffect { effect, active, proxy in
            effect.animation(DesignTokens.AnimationToken.environmentControlsHover.delay(active ? 0 : DesignTokens.EnvironmentHome.hoverDismissDelay)) {
                $0.clipShape(.capsule.size(
                    width: active ? proxy.size.width : proxy.size.height,
                    height: proxy.size.height,
                    anchor: .center
                ))
            }
        }
        .frame(
            width: DesignTokens.EnvironmentHome.compactSize.width,
            height: DesignTokens.EnvironmentHome.compactSize.height
        )
    }
}

public struct WindowRestoreIcon: View {
    public init() {}

    public var body: some View {
        WindowRestoreGlyph()
            .fill(.foreground)
            .accessibilityHidden(true)
    }
}

private struct WindowRestoreGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let extent = min(rect.width, rect.height)
        let radius = extent * 0.26
        let separation = extent * 0.27
        var path = Path()
        for direction in [-1.0, 1.0] {
            let angle = direction < 0 ? -3 * Double.pi / 4 : Double.pi / 4
            let center = CGPoint(
                x: rect.midX + cos(angle) * separation,
                y: rect.midY + sin(angle) * separation
            )
            for vertex in 0..<3 {
                let bearing = angle + Double(vertex) * 2 * Double.pi / 3
                let point = CGPoint(x: center.x + cos(bearing) * radius, y: center.y + sin(bearing) * radius)
                if vertex == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        return path
    }
}

public struct CenteredRevealShape: InsettableShape {
    public var size: CGSize
    public var cornerRadius: CGFloat

    public init(size: CGSize, cornerRadius: CGFloat) {
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    public nonisolated func path(in rect: CGRect) -> Path {
        let clamped = CGSize(
            width: min(size.width, rect.width),
            height: min(size.height, rect.height)
        )
        let centered = CGRect(
            x: rect.midX - clamped.width / 2,
            y: rect.midY - clamped.height / 2,
            width: clamped.width,
            height: clamped.height
        )
        return Path(roundedRect: centered, cornerRadius: cornerRadius, style: .continuous)
    }

    public nonisolated func inset(by amount: CGFloat) -> CenteredRevealShape {
        var copy = self
        copy.size = CGSize(
            width: max(size.width - amount * 2, 0),
            height: max(size.height - amount * 2, 0)
        )
        return copy
    }
}
