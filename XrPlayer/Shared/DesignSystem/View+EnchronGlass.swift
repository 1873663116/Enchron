import SwiftUI

// MARK: - Glass Variants (R4)

/// Four named glass effect variants from the design system.
///
/// **Important:** Apply glass effects to the *container* view, not to child views
/// inside a ZStack — otherwise the rendering is incorrect on visionOS.
extension View {

    /// Main window panels — full glass with window corner radius.
    ///
    /// Maps to: `.glassBackgroundEffect(in: .rect(cornerRadius: 40))`
    public func enchronGlassWindow() -> some View {
        self.glassBackgroundEffect(
            in: .rect(cornerRadius: DesignTokens.Radius.window)
        )
    }

    /// Control bar capsule — pill-shaped glass.
    ///
    /// Maps to: `.glassBackgroundEffect(in: .capsule)`
    public func enchronGlassControl() -> some View {
        self.glassBackgroundEffect(in: .capsule)
    }

    /// Content panels, popovers — regular material for readable content areas.
    ///
    /// Maps to: `.background(.regularMaterial)`
    public func enchronGlassPanel() -> some View {
        self.background(.regularMaterial)
    }

    /// Sidebar — no explicit modifier; system List provides default glass.
    ///
    /// This is a no-op by design. The system's NavigationSplitView sidebar
    /// already applies appropriate glass styling. Call this to document intent
    /// without adding unnecessary modifiers.
    public func enchronGlassSidebar() -> some View {
        self
    }
}
