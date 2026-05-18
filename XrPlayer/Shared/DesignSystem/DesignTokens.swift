import SwiftUI

// MARK: - Design Tokens

/// Enchron design system — the single source of truth for all visual constants.
///
/// Layers:
///   1. Primitives (Spacing, Radius, Stroke) — raw values on a grid
///   2. Semantics (Surface, AnimationToken, HoverStyle, Interactive) — intent
///   3. Components (Card, Menu, ControlBar) — assembled from 1 + 2
///
/// Usage: `DesignTokens.Spacing.md`, `DesignTokens.Card.paddingH`, etc.
public enum DesignTokens {

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Spacing (8pt grid)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// 8pt grid with 4pt half-step. Covers all layout spacing needs.
    public enum Spacing {
        /// 4 — hover gap, micro adjustment
        public static let xxs: CGFloat = 4
        /// 8 — compact padding, icon gaps
        public static let xs: CGFloat = 8
        /// 12 — medium padding, list item spacing
        public static let sm: CGFloat = 12
        /// 16 — standard padding (SwiftUI default `.padding()`)
        public static let md: CGFloat = 16
        /// 20 — panel padding, section spacing
        public static let lg: CGFloat = 20
        /// 24 — large gaps
        public static let xl: CGFloat = 24
        /// 32 — section dividers
        public static let xxl: CGFloat = 32
        /// 48 — extra-large margins
        public static let xxxl: CGFloat = 48
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Radius (concentric: inner = outer − padding)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Three-tier concentric corner radius system (8pt grid).
    ///
    /// `panel(40) → card(32) → element(24)`
    /// Each tier = outer − 8pt padding, ensuring perfect concentric nesting.
    /// Example: Menu container (card 32) with 8pt glassPadding → MenuItem (element 24).
    ///
    /// Window chrome is system-managed — do not set window corner radius manually.
    /// For non-standard nesting, use `concentric(outer:padding:)`.
    public enum Radius {
        /// 40 — large panels, settings pages, detail views
        public static let panel: CGFloat = 40
        /// 32 — cards, menus, mid-level containers (= panel − 8)
        public static let card: CGFloat = 32
        /// 24 — menu items, toolbar, inner containers (= card − 8)
        public static let element: CGFloat = 24
        /// 12 — small rounded backgrounds (tags, thumbnails). Not part of
        ///       the concentric hierarchy; use Capsule() for badge glass.
        public static let small: CGFloat = 12
        /// ∞ — circles, capsules
        public static let full: CGFloat = .greatestFiniteMagnitude

        /// Concentric inner radius for nested rounded containers.
        public static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
            max(outer - padding, 0)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shape Tokens (concrete Shape objects)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Pre-built shape objects for the three-tier hierarchy.
    ///
    /// Use these instead of manually constructing `RoundedRectangle(cornerRadius:)`
    /// at each call site. This ensures clip, glass, hover, and hit-test shapes
    /// are always identical.
    ///
    /// For badges/tags, use `Capsule()` directly — no ShapeToken needed.
    public enum ShapeToken {
        /// Large panels, settings, detail views (40pt)
        public static let panel = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        /// Cards, menu containers (32pt)
        public static let card = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        /// Menu items, toolbar, inner containers (24pt)
        public static let element = RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Interactive (tap target sizes — Apple HIG visionOS)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Button visual sizes per Apple HIG. All must achieve ≥60pt effective target.
    public enum Interactive {
        /// 28 — disclosure, auxiliary controls (needs 60pt surrounding space)
        public static let mini: CGFloat = 28
        /// 44 — standard buttons (needs ≥8pt clearance each side)
        public static let regular: CGFloat = 44
        /// 60 — navigation buttons, self-sufficient target
        public static let large: CGFloat = 60
        /// 64 — primary action (Play/Pause)
        public static let xl: CGFloat = 64
        /// 60 — menu/list row minimum height
        public static let rowHeight: CGFloat = 60
        /// 16 — minimum spacing between stacked buttons (Apple HIG)
        public static let buttonSpacing: CGFloat = 16
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Animation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Semantic animation presets covering all transition scenarios.
    public enum AnimationToken {
        /// Controls show/hide (showControls toggle)
        public static let controlsTransition: Animation = .easeInOut(duration: 0.4)
        /// Panel expand/collapse (timeline, accordion)
        public static let panelSpring: Animation = .spring(duration: 0.35, bounce: 0.15)
        /// Menu/popover popup (same curve as panel, independent tuning)
        public static let menuPopup: Animation = .spring(duration: 0.35, bounce: 0.15)
        /// Selection state change
        public static let selection: Animation = .spring(.bouncy(duration: 0.4, extraBounce: 0.1))
        /// Play/pause state
        public static let playback: Animation = .spring(response: 0.45, dampingFraction: 0.85)
        /// Cinema environment switch
        public static let scene: Animation = .spring(response: 0.3, dampingFraction: 0.7)
        /// Content fade-in
        public static let fadeIn: Animation = .easeIn(duration: 0.25)
        /// Skeleton loading pulse
        public static let skeleton: Animation = .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Surface (translucent layers on glass)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Elevation tiers for subtle depth on glass backgrounds.
    public enum Surface {
        /// Card background
        public static let card: Color = .white.opacity(0.03)
        /// Elevated panel background
        public static let elevated: Color = .white.opacity(0.04)
        /// Overlay / brighter surface
        public static let overlay: Color = .white.opacity(0.06)
        /// Selected state background
        public static let selected: Color = .white.opacity(0.08)
        /// Subtle border
        public static let border: Color = .white.opacity(0.05)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Stroke
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Line width tiers for borders and timeline marks.
    public enum Stroke {
        /// Card borders, unselected state
        public static let subtle: CGFloat = 0.5
        /// Timeline major ticks
        public static let regular: CGFloat = 1.0
        /// Playhead, selected state borders
        public static let bold: CGFloat = 1.5
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Layout
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Shared layout dimension tokens.
    public enum Layout {
        /// Width shared by PlayerControlsView and NLETimelineView panels.
        public static let playerControlsWidth: CGFloat = 680
        /// Ornament overlap with window bottom edge (Apple HIG: 20pt).
        public static let ornamentGap: CGFloat = 20
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Typography
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Semantic font mapping — always use these instead of `.system(size:)`.
    /// System Text Styles handle Dynamic Type and visionOS viewing distance automatically.
    public enum Typography {
        /// Video titles, page headings
        public static let title: Font = .title2
        /// Card titles, section labels
        public static let headline: Font = .headline
        /// Resolution, file size, date metadata
        public static let metadata: Font = .caption
        /// Section headers like "SOURCES", "VIDEO METADATA"
        public static let sectionHeader: Font = .caption2
        /// Badge labels: MV-HEVC, HDR10+
        public static let badge: Font = .caption
        /// Monospaced timecode/ruler text (9pt medium monospaced)
        public static let monospacedDetail: Font = .system(size: 9, weight: .medium, design: .monospaced)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Symbol Sizes
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Component Standards (assembled from primitives)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Video/folder card standard dimensions.
    public enum Card {
        /// Horizontal padding inside card text area
        public static let paddingH: CGFloat = Spacing.md        // 16
        /// Vertical padding inside card text area (project-wide constant)
        public static let paddingV: CGFloat = 14
        /// Adaptive grid minimum card width
        public static let gridMin: CGFloat = 240
        /// Grid inter-item spacing
        public static let gridSpacing: CGFloat = Spacing.lg     // 20
    }

    /// Menu/popover panel standard dimensions.
    public enum Menu {
        /// Glass inset padding
        public static let glassPadding: CGFloat = Spacing.xs    // 8
        /// Main menu panel width
        public static let panelWidth: CGFloat = 190
        /// Submenu panel width
        public static let submenuWidth: CGFloat = 200
    }

    /// Player control bar standard dimensions.
    public enum ControlBar {
        /// Panel width (matches Layout.playerControlsWidth)
        public static let width: CGFloat = Layout.playerControlsWidth
        /// Spacing between control buttons (≥16pt per Apple HIG)
        public static let buttonSpacing: CGFloat = Interactive.buttonSpacing
    }
}
