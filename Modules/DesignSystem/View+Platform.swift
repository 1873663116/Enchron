import SwiftUI

public enum EnchronHoverStyle {
    case automatic
    case lift
    case highlight
}

public struct EnchronHoverGroup {
    public enum Behavior {
        case activatesGroup
        case followsGroup
        case ignoresGroup
        case preservesGroup
    }

    let systemValue: HoverEffectGroup

    public init(
        id: String? = nil,
        in namespace: Namespace.ID,
        behavior: Behavior = .activatesGroup
    ) {
        let systemBehavior: HoverEffectGroup.Behavior = switch behavior {
        case .activatesGroup: .activatesGroup
        case .followsGroup: .followsGroup
        case .ignoresGroup: .ignoresGroup
        case .preservesGroup: .preservesGroup
        }
        systemValue = HoverEffectGroup(id: id, in: namespace, behavior: systemBehavior)
    }
}

private struct EnchronInsetHoverShape<Base: Shape>: Shape {
    let base: Base
    let insets: EdgeInsets

    func path(in rect: CGRect) -> Path {
        let insetRect = CGRect(
            x: rect.minX + insets.leading,
            y: rect.minY + insets.top,
            width: max(rect.width - insets.leading - insets.trailing, 0),
            height: max(rect.height - insets.top - insets.bottom, 0)
        )
        return base.path(in: insetRect)
    }
}

private func enchronInsetsAreUniform(_ insets: EdgeInsets) -> Bool {
    insets.top == insets.leading
        && insets.leading == insets.bottom
        && insets.bottom == insets.trailing
}

public extension View {
    @ViewBuilder
    func enchronGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        glassBackgroundEffect(in: shape)
    }

    @ViewBuilder
    func enchronPlateGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        glassBackgroundEffect(.plate, in: shape, displayMode: .always)
    }

    @ViewBuilder
    func enchronWindowGlassBackground(_ displayMode: GlassBackgroundDisplayMode) -> some View {
        glassBackgroundEffect(displayMode: displayMode)
    }

    @ViewBuilder
    func enchronHoverContentShape<S: Shape>(_ shape: S) -> some View {
        contentShape(.hoverEffect, shape)
    }

    @ViewBuilder
    func enchronHoverContentShape<S: InsettableShape>(
        _ shape: S,
        insets: EdgeInsets
    ) -> some View {
        let visual = EnchronInsetHoverShape(base: shape, insets: insets)
        if enchronInsetsAreUniform(insets) {
            self
                .clipShape(shape.inset(by: insets.top))
                .contentShape(.interaction, shape)
                .contentShape(.hoverEffect, shape.inset(by: insets.top))
        } else {
            self
                .clipShape(visual)
                .contentShape(.interaction, shape)
                .contentShape(.hoverEffect, visual)
        }
    }

    @ViewBuilder
    func enchronHoverEffect(
        _ style: EnchronHoverStyle = .automatic,
        in group: EnchronHoverGroup? = nil,
        isEnabled: Bool = true
    ) -> some View {
        switch style {
        case .automatic:
            hoverEffect(.automatic, in: group?.systemValue, isEnabled: isEnabled)
        case .lift:
            hoverEffect(.lift, in: group?.systemValue, isEnabled: isEnabled)
        case .highlight:
            hoverEffect(.highlight, in: group?.systemValue, isEnabled: isEnabled)
        }
    }

    @ViewBuilder
    func enchronHoverScale(
        active activeScale: CGFloat,
        inactive inactiveScale: CGFloat = 1,
        in group: EnchronHoverGroup? = nil
    ) -> some View {
        hoverEffect(in: group?.systemValue) { effect, isActive, _ in
            effect.scaleEffect(isActive ? activeScale : inactiveScale)
        }
    }

    @ViewBuilder
    func enchronHoverOpacity(
        active activeOpacity: Double,
        inactive inactiveOpacity: Double,
        in group: EnchronHoverGroup? = nil,
        forcedActive: Bool = false,
        animation: Animation? = nil
    ) -> some View {
        if let animation {
            hoverEffect(in: group?.systemValue) { effect, isActive, _ in
                effect.animation(animation) {
                    $0.opacity(isActive || forcedActive ? activeOpacity : inactiveOpacity)
                }
            }
        } else {
            hoverEffect(in: group?.systemValue) { effect, isActive, _ in
                effect.opacity(isActive || forcedActive ? activeOpacity : inactiveOpacity)
            }
        }
    }

    @ViewBuilder
    func enchronHoverOffset(
        activeY: CGFloat,
        inactiveY: CGFloat = 0,
        in group: EnchronHoverGroup? = nil,
        forcedActive: Bool = false,
        animation: Animation? = nil
    ) -> some View {
        if let animation {
            hoverEffect(in: group?.systemValue) { effect, isActive, _ in
                effect.animation(animation) {
                    $0.offset(y: isActive || forcedActive ? activeY : inactiveY)
                }
            }
        } else {
            hoverEffect(in: group?.systemValue) { effect, isActive, _ in
                effect.offset(y: isActive || forcedActive ? activeY : inactiveY)
            }
        }
    }

    @ViewBuilder
    func enchronHoverActivation(in group: EnchronHoverGroup?) -> some View {
        hoverEffect(in: group?.systemValue) { effect, _, _ in effect }
    }

    @ViewBuilder
    func enchronHoverEffectDisabled(_ disabled: Bool = true) -> some View {
        hoverEffectDisabled(disabled)
    }
}

public extension View {
    @ViewBuilder
    func enchronSpatialOffset(z: CGFloat) -> some View {
        offset(z: z)
    }

    @ViewBuilder
    func enchronSpatialFrame(depth: CGFloat) -> some View {
        frame(depth: depth)
    }
}

private struct EnchronScreenAppearance: ViewModifier {
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .onAppear {
                withAnimation(DesignTokens.AnimationToken.controlsTransition) {
                    hasAppeared = true
                }
            }
            .onDisappear { hasAppeared = false }
    }
}

public extension View {
    func enchronScreenAppearance() -> some View {
        modifier(EnchronScreenAppearance())
    }

    @ViewBuilder
    func enchronLiteralTextInput() -> some View {
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}
