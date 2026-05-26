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
        /// 36 — compact scrubbers and dense icon controls (needs surrounding clearance)
        public static let compact: CGFloat = 36
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
        /// Insert/delete list row mutation.
        public static let listMutation: Animation = .spring(response: 0.34, dampingFraction: 0.86)
        /// Play/pause state
        public static let playback: Animation = .spring(response: 0.45, dampingFraction: 0.85)
        /// Cinema environment switch
        public static let scene: Animation = .spring(response: 0.3, dampingFraction: 0.7)
        /// Spatial scene card stack settling.
        public static let sceneCarouselSettle: Animation = .spring(response: 0.34, dampingFraction: 0.94)
        /// Content fade-in
        public static let fadeIn: Animation = .easeIn(duration: 0.25)
        /// Skeleton loading pulse
        public static let skeleton: Animation = .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }

    /// Loading spinner timing. Kept separate from generic animation tokens
    /// because the paired head/tail phases must stay synchronized.
    public enum LoadingSpinner {
        public static let headAnimation: Animation = .easeOut(duration: 0.7)
        public static let tailAnimation: Animation = .easeOut(duration: 0.55)
        public static let headDuration: Duration = .milliseconds(700)
        public static let tailDuration: Duration = .milliseconds(550)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Theme
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Enchron's single theme accent, used for focused and active states.
    public enum Theme {
        public static let accent: Color = Color(red: 0.224, green: 0.773, blue: 0.733)
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Press Feedback
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Press feedback spec used by interactive surfaces that need explicit tap
    /// response outside the system ButtonStyle pipeline.
    public struct PressFeedbackSpec: @unchecked Sendable {
        public let pressedScale: CGFloat
        public let maximumVisualInset: CGFloat
        public let pressAnimation: Animation
        public let releaseAnimation: Animation
        public let holdDuration: Duration
        public let pressAnimationLabel: String
        public let releaseAnimationLabel: String
        public let holdDurationLabel: String

        public init(
            pressedScale: CGFloat,
            maximumVisualInset: CGFloat,
            pressAnimation: Animation,
            releaseAnimation: Animation,
            holdDuration: Duration,
            pressAnimationLabel: String,
            releaseAnimationLabel: String,
            holdDurationLabel: String
        ) {
            self.pressedScale = pressedScale
            self.maximumVisualInset = maximumVisualInset
            self.pressAnimation = pressAnimation
            self.releaseAnimation = releaseAnimation
            self.holdDuration = holdDuration
            self.pressAnimationLabel = pressAnimationLabel
            self.releaseAnimationLabel = releaseAnimationLabel
            self.holdDurationLabel = holdDurationLabel
        }

        public func effectivePressedScale(for size: CGSize) -> CGFloat {
            let shortestSide = min(size.width, size.height)
            guard shortestSide > 0 else { return pressedScale }

            let insetLimitedScale = 1 - (maximumVisualInset * 2 / shortestSide)
            return max(pressedScale, insetLimitedScale)
        }
    }

    /// Explicit press feedback tiers for cards, rows, controls, and icons.
    public enum PressFeedback {
        /// Broad surfaces should move subtly so the card remains spatially stable.
        public static let card = PressFeedbackSpec(
            pressedScale: 0.97,
            maximumVisualInset: 4,
            pressAnimation: .easeOut(duration: 0.08),
            releaseAnimation: .spring(response: 0.3, dampingFraction: 0.6),
            holdDuration: .milliseconds(150),
            pressAnimationLabel: "easeOut 0.08s",
            releaseAnimationLabel: "spring r0.3 d0.6",
            holdDurationLabel: "150ms"
        )

        /// Rows need a smaller movement to avoid making dense lists feel jumpy.
        public static let row = PressFeedbackSpec(
            pressedScale: 0.985,
            maximumVisualInset: 2,
            pressAnimation: .easeOut(duration: 0.06),
            releaseAnimation: .spring(response: 0.24, dampingFraction: 0.72),
            holdDuration: .milliseconds(110),
            pressAnimationLabel: "easeOut 0.06s",
            releaseAnimationLabel: "spring r0.24 d0.72",
            holdDurationLabel: "110ms"
        )

        /// Control capsules can respond more clearly because they are isolated.
        public static let control = PressFeedbackSpec(
            pressedScale: 0.96,
            maximumVisualInset: 3,
            pressAnimation: .easeOut(duration: 0.08),
            releaseAnimation: .spring(response: 0.28, dampingFraction: 0.65),
            holdDuration: .milliseconds(140),
            pressAnimationLabel: "easeOut 0.08s",
            releaseAnimationLabel: "spring r0.28 d0.65",
            holdDurationLabel: "140ms"
        )

        /// Individual icons use the strongest scale cue, matching spatial capsule controls.
        public static let icon = PressFeedbackSpec(
            pressedScale: 0.90,
            maximumVisualInset: 3.5,
            pressAnimation: .easeOut(duration: 0.08),
            releaseAnimation: .spring(response: 0.26, dampingFraction: 0.48),
            holdDuration: .milliseconds(150),
            pressAnimationLabel: "easeOut 0.08s",
            releaseAnimationLabel: "spring r0.26 d0.48",
            holdDurationLabel: "150ms"
        )
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
        /// Focused input/control border, using Enchron's single theme accent.
        public static let focusBorder: Color = Theme.accent
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
        public static let gridMin: CGFloat = 224
        /// Thumbnail height for grid cards
        public static let thumbnailHeight: CGFloat = 140
        /// Grid inter-item spacing
        public static let gridSpacing: CGFloat = Spacing.lg     // 20
    }

    /// Spatial card stack used by the Camp Scene preview.
    public enum SceneCarousel {
        public static let volumeWidthMeters: CGFloat = 2.20
        public static let volumeHeightMeters: CGFloat = 0.115
        public static let volumeDepthMeters: CGFloat = 0.46
        public static let stageWidth: CGFloat = 2_180
        public static let stageHeight: CGFloat = 640
        public static let stageDepth: CGFloat = 480
        public static let centerCardGap: CGFloat = 560
        public static let outerCardGap: CGFloat = 140
        public static let sideCardYOffset: CGFloat = 10
        public static let centerDepthOffset: CGFloat = 168
        public static let sideDepthOffset: CGFloat = 208
        public static let atmosphericFadeStart: CGFloat = 0.18
        public static let atmosphericFadeEnd: CGFloat = 1.85
        public static let atmosphericFadeMaxOpacity: CGFloat = 0.52
        public static let dragDistance: CGFloat = 250
        public static let snapThreshold: CGFloat = 0.32
        public static let maximumPredictedStepLead: CGFloat = 1.15
        public static let maximumStepPerGesture: CGFloat = 3
        public static let detailRevealDelayNanoseconds: UInt64 = 120_000_000
        public static let detailRevealDelayPerStepNanoseconds: UInt64 = 70_000_000
        public static let detailRevealStart: CGFloat = 0.48
        public static let detailRevealComplete: CGFloat = 0.10
    }

    public enum SourceSidebar {
        /// Files page source sidebar glass panel width.
        public static let width: CGFloat = 224
        /// Distance between the sidebar glass panel and the WindowGroup container edge.
        public static let windowInset: CGFloat = Spacing.xs
        /// Distance from the sidebar glass panel edge to the first content control.
        public static let trailingContentGap: CGFloat = Spacing.lg
        /// Inner horizontal padding between sidebar content and its glass panel.
        public static let contentPaddingH: CGFloat = Spacing.lg
        /// Horizontal inset for source and favorite row groups inside the glass panel.
        public static let listPaddingH: CGFloat = Spacing.xs
        /// Inner vertical padding between sidebar content and its glass panel.
        public static let contentPaddingV: CGFloat = Spacing.lg
        /// Compact visual height for source and favorite rows.
        public static let rowHeight: CGFloat = 48
        /// Vertical spacing between adjacent source rows.
        public static let rowSpacing: CGFloat = 0
        /// Inner horizontal padding for source rows.
        public static let rowPaddingH: CGFloat = Spacing.xs
        /// Compact source row shape.
        public static let rowShape = RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
        /// Section labels inside the source sidebar.
        public static let sectionTitleFont: Font = Typography.metadata
        /// Unchecked selection indicator color inside the source sidebar.
        public static let selectionIndicator: Color = .white.opacity(0.34)
        /// Width of swipe action buttons revealed behind source rows.
        public static let swipeActionWidth: CGFloat = 56
        /// Movement needed before a source row commits to horizontal swipe.
        public static let swipeActivationDistance: CGFloat = Spacing.xs
        /// Movement tolerated while waiting for reorder long press activation.
        public static let reorderPressSlop: CGFloat = Spacing.xs
        /// Long press duration before source rows enter reorder mode.
        public static let reorderLongPressDuration: Double = 0.35
        /// Momentary scale cue when a source row enters reorder mode.
        public static let reorderActivationScale: CGFloat = 1.045
        /// Duration of the reorder activation cue before settling into the lifted drag scale.
        public static let reorderActivationCueDuration: Duration = .milliseconds(160)
        /// Delay before row hover returns after reorder settles.
        public static let reorderHoverRestoreDelay: Duration = .milliseconds(420)
        /// Vertical offset used while a newly inserted source row animates in.
        public static let rowInsertionOffset: CGFloat = Spacing.sm
        /// Fraction of a row a drag must cross before the reorder placeholder moves.
        public static let reorderSwitchThreshold: CGFloat = 0.5
        /// Fraction used when dragging back toward the original slot to avoid midpoint jitter.
        public static let reorderReturnThreshold: CGFloat = 0.65
        /// Subtle lift scale while a source row is being reordered.
        public static let reorderLiftScale: CGFloat = 1.02
        /// Files page source sidebar glass container shape.
        public static let shape = ShapeToken.panel
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
        public static let buttonSpacing: CGFloat = Spacing.xl
        /// Horizontal padding inside player control capsule.
        public static let paddingH: CGFloat = Spacing.xxl
        /// Vertical padding inside player control capsule.
        public static let paddingV: CGFloat = Spacing.sm
        /// Primary play button fill.
        public static let primaryFill: Color = .white.opacity(0.72)
        /// Primary play symbol color.
        public static let primarySymbol: Color = .black.opacity(0.78)
    }

    /// Playback progress bar dimensions.
    public enum ProgressBar {
        /// Standard draggable scrubber button.
        public static let thumbDiameter: CGFloat = Interactive.mini - 4
        /// Main progress track in active drag mode.
        public static let trackHeight: CGFloat = thumbDiameter
        /// Track scale before the scrubber is clicked into active drag mode.
        public static let inactiveScale: CGFloat = 0.66
        /// Track height before active drag mode.
        public static let inactiveTrackHeight: CGFloat = trackHeight * inactiveScale
        /// Interactive strip height that contains hover target, track, and scrubber.
        public static let hitHeight: CGFloat = Interactive.large
        /// Near-invisible fill that lets the system own the 60pt hover carrier without drawing a visible control.
        public static let hoverCarrierFill: Color = .white.opacity(0.01)
        /// Imperceptible inactive opacity that keeps the carrier as a real system hover effect.
        public static let hoverCarrierInactiveOpacity: CGFloat = 0.999
        /// Review/demo width for player progress components.
        public static let previewWidth: CGFloat = Layout.playerControlsWidth
        /// Height reserved above the track for hover time readout.
        public static let timeBubbleOffset: CGFloat = Spacing.xl
        /// Padding inside hover time readout.
        public static let timeBubblePaddingH: CGFloat = Spacing.xs
        /// Padding inside hover time readout.
        public static let timeBubblePaddingV: CGFloat = Spacing.xxs
        /// Corner radius for hover time readout.
        public static let timeBubbleRadius: CGFloat = Radius.small
        /// Hover time readout background.
        public static let timeBubbleFill: Color = .white.opacity(0.16)
        /// Scrubber thumb edge, separating the button from the bright track.
        public static let thumbStroke: Color = .black.opacity(0.18)
        /// Scrubber thumb edge width.
        public static let thumbStrokeWidth: CGFloat = Stroke.regular
        /// Played portion in normal state.
        public static let playedColor: Color = .white.opacity(0.72)
        /// Played portion in hover/drag state.
        public static let playedHoverColor: Color = .white.opacity(0.95)
        /// Unplayed portion in normal state.
        public static let unplayedColor: Color = .white.opacity(0.16)
        /// Unplayed portion in hover/drag state.
        public static let unplayedHoverColor: Color = .white.opacity(0.24)
    }

    /// DesignPreview precision timeline prototype.
    public enum PrecisionTimeline {
        /// Expanded precision timeline width.
        public static let expandedWidth: CGFloat = 960
        /// Expanded precision timeline height.
        public static let expandedHeight: CGFloat = 220
        /// Vertical gap between the primary progress bar and expanded timeline.
        public static let expansionGap: CGFloat = Spacing.lg
        /// Space outside the expanded panel that accepts dismiss taps in DesignPreview.
        public static let dismissMargin: CGFloat = Spacing.xxxl
        /// Panel inner padding.
        public static let panelPadding: CGFloat = Spacing.lg
        /// Height reserved for the timecode and frame controls.
        public static let headerHeight: CGFloat = 64
        /// Time ruler height.
        public static let rulerHeight: CGFloat = 44
        /// Film strip height.
        public static let filmStripHeight: CGFloat = 72
        /// Film strip sprocket hole width.
        public static let sprocketWidth: CGFloat = Spacing.xs
        /// Film strip sprocket hole height.
        public static let sprocketHeight: CGFloat = Spacing.xxs
        /// Film strip sprocket spacing.
        public static let sprocketSpacing: CGFloat = Spacing.sm
        /// Film strip image inset from sprocket rows.
        public static let filmImageInset: CGFloat = Spacing.sm
        /// Zoom rail width.
        public static let zoomRailWidth: CGFloat = 148
        /// Zoom rail height.
        public static let zoomRailHeight: CGFloat = Spacing.xs
        /// Zoom rail thumb size.
        public static let zoomRailThumbSize: CGFloat = Spacing.sm
        /// Zoom control button size.
        public static let zoomButtonSize: CGFloat = Interactive.compact
        /// Frame-step button visual size.
        public static let frameButtonSize: CGFloat = Interactive.regular
        /// Effective frame-step button hit target.
        public static let frameButtonHitSize: CGFloat = Interactive.large
        /// Horizontal space around the center playhead for frame-step buttons.
        public static let frameButtonCenterGap: CGFloat = Spacing.xxl
        /// Center playhead line width.
        public static let playheadWidth: CGFloat = Stroke.bold
        /// Major tick height.
        public static let majorTickHeight: CGFloat = Spacing.lg
        /// Minor tick height.
        public static let minorTickHeight: CGFloat = Spacing.xs
        /// Thumbnail segment height separator width.
        public static let thumbnailSeparatorWidth: CGFloat = Stroke.subtle
        /// Thumbnail segment minimum width.
        public static let thumbnailMinWidth: CGFloat = Interactive.large
        /// Thumbnail segment width at one second per 12pt.
        public static let thumbnailSecondsScale: CGFloat = Spacing.sm
        /// Ruler target spacing for major labels.
        public static let majorTickTargetSpacing: CGFloat = 96
        /// Ruler target spacing for minor ticks.
        public static let minorTickTargetSpacing: CGFloat = 18
        /// Minimum zoom scale in pixels per second.
        public static let minPixelsPerSecond: CGFloat = 0.04
        /// Maximum zoom scale in pixels per second, enough for frame-level dragging at 24fps.
        public static let maxPixelsPerSecond: CGFloat = 288
        /// Initial zoom scale in pixels per second for the DesignPreview fixture.
        public static let initialPixelsPerSecond: CGFloat = 2.4
        /// Increment ratio used by explicit zoom buttons.
        public static let zoomStepRatio: CGFloat = 1.28
        /// Initial DesignPreview fixture duration, in seconds.
        public static let previewDuration: Double = 8_894
        /// DesignPreview fixture frame rate.
        public static let previewFrameRate: Double = 24
        /// Scale used when the expanded timeline grows out of the progress bar.
        public static let collapsedScale: CGFloat = 0.72
        /// Expanded timeline panel fill.
        public static let panelFill: Color = .black.opacity(0.22)
        /// Expanded timeline border.
        public static let panelBorder: Color = .white.opacity(0.08)
        /// Timecode foreground.
        public static let timecodeColor: Color = .white.opacity(0.92)
        /// Secondary timeline text foreground.
        public static let secondaryTextColor: Color = .white.opacity(0.46)
        /// Minor tick color.
        public static let minorTickColor: Color = .white.opacity(0.22)
        /// Major tick color.
        public static let majorTickColor: Color = .white.opacity(0.46)
        /// Center playhead color.
        public static let playheadColor: Color = .white.opacity(0.95)
        /// Timeline center accent.
        public static let playheadAccent: Color = Theme.accent
        /// Empty timeline area.
        public static let emptyAreaFill: Color = .white.opacity(0.025)
        /// Film strip top highlight.
        public static let filmStripHighlight: Color = .white.opacity(0.08)
        /// Film strip body fill.
        public static let filmStripBase: Color = .black.opacity(0.42)
        /// Film strip sprocket fill.
        public static let sprocketFill: Color = .black.opacity(0.58)
        /// Film strip separator.
        public static let filmStripSeparator: Color = .black.opacity(0.32)
        /// Zoom rail fill.
        public static let zoomRailFill: Color = .white.opacity(0.12)
        /// Zoom rail active fill.
        public static let zoomRailActiveFill: Color = Theme.accent.opacity(0.72)
        /// Subtle overlay used for controls on the timeline panel.
        public static let controlFill: Color = .white.opacity(0.08)
        /// Simulated thumbnail palette.
        public static let thumbnailPalette: [Color] = [
            Color(red: 0.10, green: 0.20, blue: 0.26),
            Color(red: 0.19, green: 0.16, blue: 0.25),
            Color(red: 0.25, green: 0.18, blue: 0.12),
            Color(red: 0.14, green: 0.24, blue: 0.18),
            Color(red: 0.28, green: 0.23, blue: 0.12),
            Color(red: 0.16, green: 0.14, blue: 0.28)
        ]
    }
}
