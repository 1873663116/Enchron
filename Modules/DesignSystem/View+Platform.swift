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

    #if os(visionOS)
    let systemValue: HoverEffectGroup
    #endif

    public init(
        id: String? = nil,
        in namespace: Namespace.ID,
        behavior: Behavior = .activatesGroup
    ) {
        #if os(visionOS)
        let systemBehavior: HoverEffectGroup.Behavior = switch behavior {
        case .activatesGroup: .activatesGroup
        case .followsGroup: .followsGroup
        case .ignoresGroup: .ignoresGroup
        case .preservesGroup: .preservesGroup
        }
        systemValue = HoverEffectGroup(id: id, in: namespace, behavior: systemBehavior)
        #endif
    }
}

public extension View {
    @ViewBuilder
    func enchronGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: shape)
        #else
        background(.regularMaterial, in: shape)
        #endif
    }

    @ViewBuilder
    func enchronPlateGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        #if os(visionOS)
        glassBackgroundEffect(.plate, in: shape, displayMode: .always)
        #else
        background(.regularMaterial, in: shape)
        #endif
    }

    @ViewBuilder
    func enchronHoverContentShape<S: Shape>(_ shape: S) -> some View {
        #if os(visionOS)
        contentShape(.hoverEffect, shape)
        #else
        contentShape(shape)
        #endif
    }

    @ViewBuilder
    func enchronHoverEffect(
        _ style: EnchronHoverStyle = .automatic,
        in group: EnchronHoverGroup? = nil,
        isEnabled: Bool = true
    ) -> some View {
        #if os(visionOS)
        switch style {
        case .automatic:
            hoverEffect(.automatic, in: group?.systemValue, isEnabled: isEnabled)
        case .lift:
            hoverEffect(.lift, in: group?.systemValue, isEnabled: isEnabled)
        case .highlight:
            hoverEffect(.highlight, in: group?.systemValue, isEnabled: isEnabled)
        }
        #else
        modifier(MacPointerHoverModifier(style: style, isEnabled: isEnabled))
        #endif
    }

    @ViewBuilder
    func enchronHoverScale(
        active activeScale: CGFloat,
        inactive inactiveScale: CGFloat = 1,
        in group: EnchronHoverGroup? = nil
    ) -> some View {
        #if os(visionOS)
        hoverEffect(in: group?.systemValue) { effect, isActive, _ in
            effect.scaleEffect(isActive ? activeScale : inactiveScale)
        }
        #else
        modifier(
            MacPointerScaleModifier(
                activeScale: activeScale,
                inactiveScale: inactiveScale
            )
        )
        #endif
    }

    @ViewBuilder
    func enchronHoverOpacity(
        active activeOpacity: Double,
        inactive inactiveOpacity: Double,
        in group: EnchronHoverGroup? = nil,
        forcedActive: Bool = false,
        animation: Animation? = nil,
        macShowsActive: Bool = true,
        macUsesLocalHover: Bool = false
    ) -> some View {
        #if os(visionOS)
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
        #else
        modifier(
            MacPointerOpacityModifier(
                activeOpacity: activeOpacity,
                inactiveOpacity: inactiveOpacity,
                forcedActive: forcedActive,
                animation: animation,
                followsGroup: group != nil && macUsesLocalHover == false,
                macShowsActive: macShowsActive
            )
        )
        #endif
    }

    @ViewBuilder
    func enchronHoverOffset(
        activeY: CGFloat,
        inactiveY: CGFloat = 0,
        in group: EnchronHoverGroup? = nil,
        forcedActive: Bool = false,
        animation: Animation? = nil
    ) -> some View {
        #if os(visionOS)
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
        #else
        offset(y: forcedActive ? activeY : inactiveY)
            .animation(animation ?? .easeOut(duration: 0.16), value: forcedActive)
        #endif
    }

    @ViewBuilder
    func enchronHoverActivation(in group: EnchronHoverGroup?) -> some View {
        #if os(visionOS)
        hoverEffect(in: group?.systemValue) { effect, _, _ in effect }
        #else
        self
        #endif
    }

    @ViewBuilder
    func enchronHoverEffectDisabled(_ disabled: Bool = true) -> some View {
        #if os(visionOS)
        hoverEffectDisabled(disabled)
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct MacPointerHoverModifier: ViewModifier {
    let style: EnchronHoverStyle
    let isEnabled: Bool

    @State private var isHovering = false

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .automatic, .highlight:
            content
                .brightness(isEnabled && isHovering ? 0.06 : 0)
                .animation(.easeOut(duration: 0.16), value: isHovering)
                .onHover { isHovering = $0 }
        case .lift:
            content
                .scaleEffect(isEnabled && isHovering ? 1.025 : 1)
                .shadow(
                    color: .black.opacity(isEnabled && isHovering ? 0.22 : 0),
                    radius: isEnabled && isHovering ? 12 : 0,
                    y: isEnabled && isHovering ? 5 : 0
                )
                .animation(.easeOut(duration: 0.16), value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

private struct MacPointerScaleModifier: ViewModifier {
    let activeScale: CGFloat
    let inactiveScale: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? activeScale : inactiveScale)
            .animation(.easeOut(duration: 0.16), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

private struct MacPointerOpacityModifier: ViewModifier {
    let activeOpacity: Double
    let inactiveOpacity: Double
    let forcedActive: Bool
    let animation: Animation?
    let followsGroup: Bool
    let macShowsActive: Bool

    @State private var isHovering = false

    private var isActive: Bool {
        forcedActive || (followsGroup ? macShowsActive : isHovering)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? activeOpacity : inactiveOpacity)
            .animation(animation ?? .easeOut(duration: 0.16), value: isActive)
            .onHover { isHovering = $0 }
    }
}
#endif


public extension View {
    @ViewBuilder
    func enchronSpatialOffset(z: CGFloat) -> some View {
        #if os(visionOS)
        offset(z: z)
        #else
        self
        #endif
    }

    @ViewBuilder
    func enchronSpatialFrame(depth: CGFloat) -> some View {
        #if os(visionOS)
        frame(depth: depth)
        #else
        self
        #endif
    }
}


public extension View {
    @ViewBuilder
    func enchronLiteralTextInput() -> some View {
        #if os(visionOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}
