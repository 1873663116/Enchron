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

    func enchronGlassControl() -> some View {
        self
            .clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
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
