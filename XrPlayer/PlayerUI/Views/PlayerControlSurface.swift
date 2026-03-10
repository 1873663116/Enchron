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
        let cornerRadius = size * 0.32
        let strokeOpacity = isSelected ? 0.32 : 0.12
        let shadowOpacity = prominence == .primary ? 0.12 : 0.08

        content
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(strokeOpacity),
                        lineWidth: isSelected ? 1.25 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 12, y: 6)
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: isPressed)
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
