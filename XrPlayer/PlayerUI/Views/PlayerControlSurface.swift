import SwiftUI

enum PlayerControlProminence {
    case primary
    case secondary
}

struct PlayerControlSurfaceStyle: ButtonStyle {
    let size: CGFloat
    var isSelected: Bool = false
    var prominence: PlayerControlProminence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .playerControlSurface(
                size: size,
                isSelected: isSelected,
                prominence: prominence,
                isPressed: configuration.isPressed
            )
    }
}

private struct PlayerControlSurfaceModifier: ViewModifier {
    let size: CGFloat
    let isSelected: Bool
    let prominence: PlayerControlProminence
    let isPressed: Bool

    func body(content: Content) -> some View {
        // Aesthetic Refinement: More organic corner radius, refined glass materials, and spatial depth
        let cornerRadius = size * 0.35 
        let strokeOpacity = isSelected ? 0.45 : 0.15
        let shadowOpacity = prominence == .primary ? 0.15 : 0.1

        content
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial) // Refined spatial glass material
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.9) : Color.white.opacity(strokeOpacity),
                        lineWidth: isSelected ? 1.5 : 0.5 // Thinner stroke for elegance
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .hoverEffect() // Native gaze-to-interact visual feedback
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 15, x: 0, y: 8)
            .scaleEffect(isPressed ? 0.92 : 1.0) // More tactile compression
            .animation(.spring(response: 0.25, dampingFraction: 0.7, blendDuration: 0), value: isPressed)
    }
}

extension View {
    func playerControlSurface(
        size: CGFloat,
        isSelected: Bool = false,
        prominence: PlayerControlProminence = .secondary,
        isPressed: Bool = false
    ) -> some View {
        modifier(
            PlayerControlSurfaceModifier(
                size: size,
                isSelected: isSelected,
                prominence: prominence,
                isPressed: isPressed
            )
        )
    }
}
