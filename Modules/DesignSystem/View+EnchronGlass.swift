import SwiftUI

public extension View {

    func enchronButtonSurface<S: InsettableShape>(in shape: S) -> some View {
        background(.thickMaterial, in: shape)
            .overlay {
                shape.stroke(
                    DesignTokens.Surface.chromeBorder,
                    lineWidth: DesignTokens.Stroke.subtle
                )
            }
    }

    func enchronGlassWindow() -> some View {
        let shape = DesignTokens.ShapeToken.panel
        return self
            .clipShape(shape)
            .background(.regularMaterial, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    func enchronGlassControl() -> some View {
        self
            .clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.automatic)
            .contentShape(Capsule())
    }

    func enchronGlassPanel() -> some View {
        let shape = DesignTokens.ShapeToken.panel
        return self
            .clipShape(shape)
            .background(.regularMaterial, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    func enchronGlassCard() -> some View {
        let shape = DesignTokens.ShapeToken.card
        return self
            .clipShape(shape)
            .background(DesignTokens.Surface.card, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
            .enchronHoverEffect(.lift)
    }

    func enchronGlassMenuItem() -> some View {
        let shape = DesignTokens.ShapeToken.element
        return self
            .clipShape(shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
            .enchronHoverEffect(.highlight)
    }

    func enchronGlassMenu() -> some View {
        let shape = DesignTokens.ShapeToken.card
        return self
            .clipShape(shape)
            .background(.regularMaterial, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    func enchronGlassToolbar() -> some View {
        let shape = DesignTokens.ShapeToken.element
        return self
            .clipShape(shape)
            .background(DesignTokens.Surface.elevated, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    func enchronGlassBadge() -> some View {
        self
            .clipShape(Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .enchronHoverContentShape(Capsule())
            .contentShape(Capsule())
    }

    func enchronGlassPill() -> some View {
        self
            .clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .contentShape(Capsule())
            .enchronHoverEffect(.lift)
    }

    func enchronGlassSidebar() -> some View {
        self
    }
}
