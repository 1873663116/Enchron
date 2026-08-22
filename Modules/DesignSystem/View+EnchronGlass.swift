import SwiftUI

// MARK: - Surface Variants

/// Named surface variants for the Enchron design system.
///
/// Each modifier binds the relevant shape layers at its current bounds:
///   1. `clipShape` — visual boundary
///   2. DesignTokens or system material — visual hierarchy
///   3. `contentShape(.hoverEffect, ...)` — hover highlight region
///   4. `contentShape(.interaction, ...)` — hit-test region
///
/// Later wrappers that enlarge interaction bounds must use
/// `enchronHoverContentShape(_:insets:)` to keep hover at the visual bounds.
///
/// visionOS window roots already supply glass. Reusable controls use these
/// non-glass tiers so callers cannot create a second material boundary inside
/// a window. Window roots, ornaments, and spatial attachments opt into platform
/// glass directly through `enchronGlassBackground(in:)` at their host site.
public extension View {

    // ── Button surface ──

    /// The surface every button component sits on: a thick system material so the
    /// control reads as its own plate rather than a tint of the glass behind it,
    /// plus a 1pt white rim that holds the control's boundary over bright
    /// passthrough. Callers supply the shape they already clip and hit-test on,
    /// so the fill, the rim, and the hover region stay on one geometry.
    func enchronButtonSurface<S: InsettableShape>(in shape: S) -> some View {
        background(.thickMaterial, in: shape)
            .overlay {
                shape.strokeBorder(
                    DesignTokens.Surface.chromeBorder,
                    lineWidth: DesignTokens.Stroke.regular
                )
            }
    }

    // ── Container-level glass ──

    /// Large panel with the regular material hierarchy used inside a window.
    func enchronGlassWindow() -> some View {
        let shape = DesignTokens.ShapeToken.panel
        return self
            .clipShape(shape)
            .background(.regularMaterial, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    /// Pill-shaped control surface for content already hosted by glass.
    func enchronGlassControl() -> some View {
        self
            .clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.automatic)
            .contentShape(Capsule())
    }

    /// Content panels, popovers — regular material for readable content areas.
    func enchronGlassPanel() -> some View {
        let shape = DesignTokens.ShapeToken.panel
        return self
            .clipShape(shape)
            .background(.regularMaterial, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    // ── Interactive element glass (shape + hover bound together) ──

    /// Video/folder cards with card corner radius and `.lift` hover.
    func enchronGlassCard() -> some View {
        let shape = DesignTokens.ShapeToken.card
        return self
            .clipShape(shape)
            .background(DesignTokens.Surface.card, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
            .enchronHoverEffect(.lift)
    }

    /// Menu/list items — glass with element radius + `.highlight` hover.
    /// Use for rows in menus, popovers, and dense lists.
    func enchronGlassMenuItem() -> some View {
        let shape = DesignTokens.ShapeToken.element
        return self
            .clipShape(shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
            .enchronHoverEffect(.highlight)
    }

    /// Menu popover container with card corner radius and no hover.
    /// MenuItems inside use `element` radius, creating concentric nesting
    /// with `Menu.glassPadding` (8pt) between them: card(32) − 8 = element(24).
    func enchronGlassMenu() -> some View {
        let shape = DesignTokens.ShapeToken.card
        return self
            .clipShape(shape)
            .background(.regularMaterial, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    /// Toolbar / timeline / ruler strips with element radius and no hover.
    /// Use for narrow tool strips embedded within panels.
    func enchronGlassToolbar() -> some View {
        let shape = DesignTokens.ShapeToken.element
        return self
            .clipShape(shape)
            .background(DesignTokens.Surface.elevated, in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    /// Badges, tags, small labels — ultra-thin material in capsule shape.
    func enchronGlassBadge() -> some View {
        self
            .clipShape(Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .enchronHoverContentShape(Capsule())
            .contentShape(Capsule())
    }

    /// Filter pills / capsule buttons — button surface + `.lift` hover.
    func enchronGlassPill() -> some View {
        self
            .clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .contentShape(Capsule())
            .enchronHoverEffect(.lift)
    }

    /// Sidebar — no explicit modifier; system NavigationSplitView provides glass.
    func enchronGlassSidebar() -> some View {
        self
    }
}
