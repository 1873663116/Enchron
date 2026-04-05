import SwiftUI

// MARK: - Design Tokens

/// Enchron design system constants derived from the verified HTML mockups
/// and design-to-swiftui.md translation guide.
///
/// Usage: `DesignTokens.Radius.card`, `DesignTokens.Typography.title`, etc.
public enum DesignTokens {

    // MARK: - Radius (R2)

    /// Corner radius tokens mapped from CSS variables.
    ///
    /// **Concentric inner radius rule:**
    /// When nesting rounded containers, calculate `innerRadius = outerRadius - padding`
    /// to achieve visually concentric corners. SwiftUI's `ContainerRelativeShape()`
    /// matches shape type but does NOT subtract padding automatically.
    public enum Radius {
        /// Video cards, content panels (--radius-card: 1.25rem)
        public static let card: CGFloat = 20
        /// Main window panels (--radius-window: 2.5rem)
        public static let window: CGFloat = 40
        /// Small badges, tags (--radius-badge: 0.625rem)
        public static let badge: CGFloat = 10
    }

    // MARK: - Layout

    /// Shared layout dimension tokens.
    public enum Layout {
        /// Width shared by PlayerControlsView and NLETimelineView panels.
        public static let playerControlsWidth: CGFloat = 680
        /// Gap between navigation ornament and window edge.
        public static let ornamentGap: CGFloat = 20
    }

    // MARK: - Typography (R3)

    /// Semantic font mapping — always use these instead of `.system(size:)`.
    /// System Text Styles handle Dynamic Type and visionOS viewing distance automatically.
    public enum Typography {
        /// Video titles, page headings (text-xl font-bold)
        public static let title: Font = .title2
        /// Card titles, section labels (text-sm font-semibold)
        public static let headline: Font = .headline
        /// Resolution, file size, date metadata (text-[11px])
        public static let metadata: Font = .caption
        /// Section headers like "SOURCES", "VIDEO METADATA" (text-[10px] uppercase)
        public static let sectionHeader: Font = .caption2
        /// Badge labels: MV-HEVC, HDR10+ (text-xs)
        public static let badge: Font = .caption
        /// Monospaced timecode/ruler text (9pt medium monospaced)
        public static let monospacedDetail: Font = .system(size: 9, weight: .medium, design: .monospaced)
    }

    // MARK: - Symbol Sizes

    /// SF Symbol font tokens — centralized sizing for icon consistency.
    public enum SymbolSize {
        /// Control icons: skip, seek buttons (24pt semibold)
        public static let control: Font = .system(size: 24, weight: .semibold)
        /// Card and folder icons (36pt)
        public static let card: Font = .system(size: 36)
        /// Play/pause primary action (36pt medium)
        public static let action: Font = .system(size: 36, weight: .medium)
        /// Scene selector, large UI icons (44pt)
        public static let feature: Font = .system(size: 44)
        /// Hero detail view icons (48pt)
        public static let hero: Font = .system(size: 48)
        /// Empty state placeholder icons (60pt)
        public static let giant: Font = .system(size: 60)
    }
}
