import SwiftUI

// MARK: - Glass Variants

/// Named glass effect variants for the Enchron design system.
///
/// Each modifier binds **four shape layers** in one call:
///   1. `clipShape` — visual boundary
///   2. `glassBackgroundEffect(in:)` — material boundary
///   3. `contentShape(.hoverEffect, ...)` — hover highlight region
///   4. `contentShape(.interaction, ...)` — hit-test region
///
/// This guarantees that clip, glass, hover, and tap shapes are always
/// identical. Call sites never need to construct shapes manually.
///
/// **Rule:** Apply glass effects to the *container* view, not to child views
/// inside a ZStack — otherwise the rendering is incorrect on visionOS.
///
/// **Philosophy:** Glass everywhere. Every surface that can carry glass, should.
/// CTA / emphasis buttons use `.borderless` with custom backgrounds instead.
public extension View {

    // ── Container-level glass ──

    /// Large panel — full glass with panel corner radius.
    /// Note: visionOS window chrome is system-managed; use this for large
    /// sub-panels inside a window, not for the window itself.
    /// Prefer `enchronGlassPanel()` for content panels with regularMaterial.
    func enchronGlassWindow() -> some View {
        let shape = DesignTokens.ShapeToken.panel
        return self
            .clipShape(shape)
            .enchronGlassBackground(in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    /// Control bar / ornament — pill-shaped glass capsule.
    func enchronGlassControl() -> some View {
        self
            .clipShape(Capsule())
            .enchronGlassBackground(in: Capsule())
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

    /// Video/folder cards — glass with card corner radius + `.lift` hover.
    func enchronGlassCard() -> some View {
        let shape = DesignTokens.ShapeToken.card
        return self
            .clipShape(shape)
            .enchronGlassBackground(in: shape)
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

    /// Menu popover container — glass with card corner radius (no hover).
    /// MenuItems inside use `element` radius, creating concentric nesting
    /// with `Menu.glassPadding` (8pt) between them: card(32) − 8 = element(24).
    func enchronGlassMenu() -> some View {
        let shape = DesignTokens.ShapeToken.card
        return self
            .clipShape(shape)
            .enchronGlassBackground(in: shape)
            .enchronHoverContentShape(shape)
            .contentShape(shape)
    }

    /// Toolbar / timeline / ruler strips — compact glass with element radius (no hover).
    /// Use for narrow tool strips embedded within panels.
    func enchronGlassToolbar() -> some View {
        let shape = DesignTokens.ShapeToken.element
        return self
            .clipShape(shape)
            .enchronGlassBackground(in: shape)
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

    /// Filter pills / capsule buttons — capsule glass + `.lift` hover.
    func enchronGlassPill() -> some View {
        self
            .clipShape(Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .enchronHoverContentShape(Capsule())
            .contentShape(Capsule())
            .enchronHoverEffect(.lift)
    }

    /// Sidebar — no explicit modifier; system NavigationSplitView provides glass.
    func enchronGlassSidebar() -> some View {
        self
    }
}
