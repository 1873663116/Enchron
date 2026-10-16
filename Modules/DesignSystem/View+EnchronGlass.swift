import SwiftUI

public extension View {

    func enchronButtonSurface<S: InsettableShape>(in shape: S) -> some View {
        background(.ultraThickMaterial, in: shape)
            .overlay {
                shape.stroke(
                    DesignTokens.Surface.chromeBorder,
                    lineWidth: DesignTokens.Stroke.subtle
                )
            }
    }

    func enchronGlassControlSurface() -> some View {
        clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
    }

    func enchronCardSurface<S: InsettableShape>(in shape: S) -> some View {
        background(.ultraThickMaterial, in: shape)
            .overlay {
                shape.strokeBorder(
                    DesignTokens.Surface.overlay,
                    lineWidth: DesignTokens.Stroke.regular
                )
            }
    }

    func enchronGlassControl() -> some View {
        enchronGlassControlSurface()
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.automatic)
            .contentShape(Capsule())
    }

    func enchronGlassBadge() -> some View {
        self
            .clipShape(Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .enchronHoverContentShape(Capsule())
            .contentShape(Capsule())
    }

}
