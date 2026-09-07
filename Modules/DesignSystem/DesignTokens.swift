import Foundation
import SwiftUI

public enum DesignTokens {

    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    public enum Radius {
        public static let panel: CGFloat = 40
        public static let card: CGFloat = 32
        public static let element: CGFloat = 24
        public static let small: CGFloat = 12
        public static let full: CGFloat = .greatestFiniteMagnitude

        public static func concentric(outer: CGFloat, padding: CGFloat) -> CGFloat {
            max(outer - padding, 0)
        }
    }

    public enum ShapeToken {
        public static let panel = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        public static let card = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        public static let element = RoundedRectangle(cornerRadius: Radius.element, style: .continuous)
    }

    public enum Interactive {
        public static let mini: CGFloat = 28
        public static let compact: CGFloat = 36
        public static let regular: CGFloat = 44
        public static let large: CGFloat = 60
        public static let xl: CGFloat = 64
        public static let rowHeight: CGFloat = 60
        public static let buttonSpacing: CGFloat = 16
    }

    public enum AnimationToken {
        public static let controlsTransition: Animation = .easeInOut(duration: 0.4)
        public static let panelSpring: Animation = .spring(duration: 0.35, bounce: 0.15)
        public static let panelContentExit: Animation = .easeOut(duration: 0.12)
        public static let panelContentEntrance: Animation = .easeIn(duration: 0.18)
        public static let menuPopup: Animation = .spring(duration: 0.35, bounce: 0.15)
        public static let selection: Animation = .spring(.bouncy(duration: 0.4, extraBounce: 0.1))
        public static let listMutation: Animation = .spring(response: 0.34, dampingFraction: 0.86)
        public static let playback: Animation = .spring(response: 0.45, dampingFraction: 0.85)
        public static let scene: Animation = .spring(response: 0.3, dampingFraction: 0.7)
        public static let sceneCarouselSettle: Animation = .spring(response: 0.34, dampingFraction: 0.94)
        public static let fadeIn: Animation = .easeIn(duration: 0.25)
        public static let levelTransition: Animation = .easeOut(duration: 0.25)
        public static let levelExitDuration: Double = 0.12
        public static let levelEnterDuration: Double = 0.25
        public static let informationReveal: Animation = .easeOut(duration: 0.2)
        public static let skeleton: Animation = .easeInOut(duration: 1.0).repeatForever(autoreverses: true)

        public static let symbolRotateSpeed: Double = 2.0
        public static var symbolRotateSpin: Animation {
            .spring(response: 1.0 / symbolRotateSpeed, dampingFraction: 0.86)
        }
    }

    public struct ScrimKeyframe: Sendable {
        public let location: Double
        public let opacity: Double
        public let curve: UnitCurve

        public init(location: Double, opacity: Double, curve: UnitCurve) {
            self.location = location
            self.opacity = opacity
            self.curve = curve
        }

        public static func stops(_ keyframes: [ScrimKeyframe], sampleCount: Int) -> [Gradient.Stop] {
            (0...sampleCount).map { index in
                let t = Double(index) / Double(sampleCount)
                return Gradient.Stop(color: .black.opacity(opacity(at: t, in: keyframes)), location: t)
            }
        }

        static func opacity(at location: Double, in keyframes: [ScrimKeyframe]) -> Double {
            guard let first = keyframes.first, let last = keyframes.last else { return 0 }
            guard location > first.location else { return first.opacity }
            guard location < last.location else { return last.opacity }
            for (start, end) in zip(keyframes, keyframes.dropFirst()) where location <= end.location {
                let span = end.location - start.location
                let progress = span > 0 ? (location - start.location) / span : 1
                return start.opacity + (end.opacity - start.opacity) * end.curve.value(at: progress)
            }
            return last.opacity
        }
    }

    public enum TransitionToken {
        @MainActor public static var levelReplace: AnyTransition {
            .asymmetric(
                insertion: .opacity.animation(
                    .easeOut(duration: AnimationToken.levelEnterDuration)
                        .delay(AnimationToken.levelExitDuration)
                ),
                removal: .opacity.animation(
                    .easeIn(duration: AnimationToken.levelExitDuration)
                )
            )
        }
    }

    public enum LoadingSpinner {
        public static let cycleDuration: Duration = .milliseconds(5400)
        public static let cycleDurationMilliseconds: Double = 5400
        public static let expandCollapseDurationMilliseconds: Double = 667
        public static let constantRotationDegrees: Double = 1520
        public static let extraDegreesPerCycle: Double = 250
        public static let tailDegreesOffset: Double = -20
        public static let cyclesPerLoop: Int = 4
        public static let expandDelaysMilliseconds: [Double] = [0, 1350, 2700, 4050]
        public static let collapseDelaysMilliseconds: [Double] = [667, 2017, 3367, 4717]
    }

    public enum Theme {
        public static let accent: Color = Color(red: 0.957, green: 0.878, blue: 0.910)
        public static let surfaceContainerHighest: Color = .white.opacity(0.12)
        public static let onSurfaceVariant: Color = .white.opacity(0.68)
        public static let tertiary: Color = accent
    }

    public enum AudioSpectrum {
        public static let barSpacing: CGFloat = 6
        public static let horizontalInset: CGFloat = Spacing.xxxl
        public static let verticalInset: CGFloat = Spacing.xxl
        public static let barColor: Color = Theme.accent
    }

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

    public enum PressFeedback {
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

    public enum Surface {
        public static let card: Color = .primary.opacity(0.03)
        public static let elevated: Color = .primary.opacity(0.04)
        public static let overlay: Color = .primary.opacity(0.06)
        public static let selected: Color = .primary.opacity(0.08)
        public static let border: Color = .primary.opacity(0.05)
        public static let divider: Color = .primary.opacity(0.14)
        public static let supportingText: Color = .primary.opacity(0.72)
        public static let textScrimCoverageFraction: CGFloat = 0.8
        public static let textScrimPlateauFraction: CGFloat = 0.4
        public static let textScrimOpacity: Double = 1
        public static let textScrimSampleCount: Int = 24
        public static var textScrimMaterial: Material { .ultraThickMaterial }
        public static func textScrimKeyframes(leadFraction: Double) -> [ScrimKeyframe] {
            [
                ScrimKeyframe(location: 0, opacity: 0, curve: .linear),
                ScrimKeyframe(location: leadFraction, opacity: textScrimOpacity, curve: .easeInOut),
                ScrimKeyframe(location: 1, opacity: textScrimOpacity, curve: .linear)
            ]
        }
        public static func textScrimStops(leadFraction: Double) -> [Gradient.Stop] {
            ScrimKeyframe.stops(
                textScrimKeyframes(leadFraction: leadFraction),
                sampleCount: textScrimSampleCount
            )
        }
        public static let accessoryText: Color = .primary.opacity(0.88)
        public static let selectionHeaderText: Color = .primary
        public static let focusBorder: Color = Theme.accent
        public static let edgeStrokeOpacity: Double = 0.25
        public static let chromeBorder: Color = Theme.accent.opacity(edgeStrokeOpacity)
    }

    public enum Stroke {
        public static let subtle: CGFloat = 0.5
        public static let regular: CGFloat = 1.0
        public static let bold: CGFloat = 1.5
    }

    public enum Layout {
        public static let playerControlsContentWidth: CGFloat = 680
        public static let expandedPlayerControlsContentWidth: CGFloat = 880
        public static let playbackMediaInfoHeight: CGFloat = 72
        public static let ornamentGap: CGFloat = 20
        public static let windowEdgeFadeHeight: CGFloat = 64
    }

    public enum Typography {
        public static let title: Font = .title2
        public static let headline: Font = .headline
        public static let metadata: Font = .caption
        public static let sectionHeader: Font = .caption2
        public static let selectionHeader: Font = .body
        public static let badge: Font = .caption
        public static let monospacedDetail: Font = .system(size: 9, weight: .medium, design: .monospaced)
    }

    public enum ButtonIcon {
        public static let compactArtwork: CGFloat = 16
        public static let standardArtwork: CGFloat = 20
        public static let primaryArtwork: CGFloat = 32
        public static let labelArtwork: CGFloat = 14
    }

    public enum SymbolSize {
        public static let compact: Font = .system(
            size: ButtonIcon.compactArtwork,
            weight: .semibold
        )
        public static let control: Font = .system(
            size: ButtonIcon.standardArtwork,
            weight: .semibold
        )
        public static let label: Font = .system(
            size: ButtonIcon.labelArtwork,
            weight: .semibold
        )
        public static let selectionHeaderIcon: Font = .system(size: 22, weight: .regular)
        public static let card: Font = .system(size: 36)
        public static let action: Font = .system(
            size: ButtonIcon.primaryArtwork,
            weight: .medium
        )
        public static let feature: Font = .system(size: 44)
        public static let hero: Font = .system(size: 48)
        public static let giant: Font = .system(size: 60)
    }

    public enum Card {
        public static let paddingH: CGFloat = Spacing.md
        public static let paddingV: CGFloat = 14
        public static let gridMin: CGFloat = 224
        public static let posterWidth: CGFloat = 180
        public static let stillWidth: CGFloat = 304
        public static let stillHeight: CGFloat = 205
        public static let thumbnailHeight: CGFloat = 140
        public static let gridSpacing: CGFloat = Spacing.md
        public static let gridRevealDuration: Double = 0.25
        public static let gridRevealLayoutDelay: Double = 0.016
        public static let gridRevealPrefetchCount: Int = 24
        public static let placeholderIconSize: CGFloat = 45
    }

    public enum EnvironmentCard {
        public static let width: CGFloat = 500
        public static let height: CGFloat = 548
        public static let informationHeight: CGFloat = 188
        public static let cornerRadius: CGFloat = Radius.card
        public static let chromePadding: CGFloat = 18
        public static let informationPaddingH: CGFloat = 36
        public static let informationPaddingTop: CGFloat = 34
        public static let informationPaddingBottom: CGFloat = 14
        public static let secondaryTextOpacity: CGFloat = 0.72
        public static let informationFadeMinOpacity: CGFloat = 0
        public static let informationFadeMaxOpacity: CGFloat = 0.45
        public static let topMultiplyHeight: CGFloat = 160
        public static let topFadeMaxOpacity: CGFloat = 0.40
        public static let atmosphericContrastReduction: CGFloat = 0.68
        public static let atmosphericDesaturation: CGFloat = 0.38
        public static let atmosphericBlurRadius: CGFloat = 2.6
    }

    public enum EnvironmentCarousel {
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
        public static let centerHitTestingDistance: CGFloat = 0.12
        public static let stableRenderCardDistance: CGFloat = 1.55
        public static let motionRenderCardDistance: CGFloat = 2.18
        public static let fullOpacityDistance: CGFloat = 0.10
        public static let firstSideOpacityDistance: CGFloat = 1.00
        public static let fullFadeDistance: CGFloat = 2.18
        public static let firstSideOpacity: CGFloat = 0.85
        public static let edgeExitStart: CGFloat = 1.35
        public static let edgeExitEnd: CGFloat = 2.18
        public static let edgeSlideOutDistance: CGFloat = 300
        public static let edgeDepthRetreat: CGFloat = 42
        public static let edgeAtmosphericBoost: CGFloat = 0.42
        public static let zIndexBase: Double = 100
        public static let zIndexDistanceStep: Double = 10
    }

    public enum SourceConnection {
        public static let panelWidth: CGFloat = 420
        public static let credentialRevealDelay: Double = 0.18
        public static let disabledActionOpacity: Double = 0.5
        public static let successHoldDuration: Duration = .seconds(1)
        public static let failureColor: Color = .red
        public static let timeoutColor: Color = .orange
        public static let successColor: Color = Theme.accent
    }

    public enum EmbyDetail {
        public static let heroHeightFraction: CGFloat = 0.82
        public static let heroMinimumHeight: CGFloat = 520
        public static let logoMaxWidth: CGFloat = 460
        public static let logoMaxHeight: CGFloat = 160
        public static let overviewMaxWidth: CGFloat = 720
        public static let creditMaxWidth: CGFloat = 320
        public static let aboutCardWidth: CGFloat = 520
        public static let aboutColumnWidth: CGFloat = 260
        public static let backdropRequestWidth = 2048
        public static let titleWashStrength: Double = 0.4
        public static let titleWashSpread: CGFloat = 1.7
        public static let topContentInset: CGFloat = DesignTokens.Interactive.large + Spacing.lg * 2
        public static let backdropFadeFraction: CGFloat = 0.7
        public static let heroSettleFraction: CGFloat = 0.35
        public static let backdropWaitLimit: Double = 1.5
        public static let backdropPollInterval: Double = 0.016
        public static let backdropEntranceDuration: Double = 0.4
        public static let heroEntranceDelay: Double = 0.5
        public static let entranceDuration: Double = 0.35
        public static let entranceStagger: Double = 0.15
        public static let entranceTravel: CGFloat = 40
        public static let entrancePrefetchCount: Int = 12
        public static let sidebarHandoffDelay: Double = 0.45
    }

    public enum Collapsible {
        public static let collapsedHeight: CGFloat = 200
        public static let expandedWidth: CGFloat = 420
        public static let expandedMaxHeight: CGFloat = 520
    }

    public enum SourceSidebar {
        public static let width: CGFloat = 280
        public static let windowInset: CGFloat = Spacing.xs
        public static let trailingContentGap: CGFloat = Spacing.lg
        public static let contentPaddingH: CGFloat = Spacing.lg
        public static let listPaddingH: CGFloat = Spacing.md
        public static let contentPaddingV: CGFloat = Spacing.xl
        public static let headerContentGap: CGFloat = Spacing.lg
        public static let rowHeight: CGFloat = Interactive.rowHeight
        public static let rowSpacing: CGFloat = .zero
        public static let rowPaddingH: CGFloat = Spacing.xs
        public static let rowCornerRadius = Radius.concentric(
            outer: Radius.panel,
            padding: listPaddingH
        )
        public static let sectionTitleFont: Font = Typography.headline.weight(.bold)
        public static let selectionIndicator: Color = .white.opacity(0.34)
        public static let swipeActionWidth: CGFloat = 56
        public static let swipeActivationDistance: CGFloat = Spacing.xs
        public static let reorderPressSlop: CGFloat = Spacing.xs
        public static let reorderLongPressDuration: Double = 0.35
        public static let reorderActivationScale: CGFloat = 1.045
        public static let reorderActivationCueDuration: Duration = .milliseconds(160)
        public static let reorderHoverRestoreDelay: Duration = .milliseconds(420)
        public static let rowInsertionOffset: CGFloat = Spacing.sm
        public static let reorderSwitchThreshold: CGFloat = 0.5
        public static let reorderReturnThreshold: CGFloat = 0.65
        public static let reorderLiftScale: CGFloat = 1.02
        public static let shape = ShapeToken.panel
    }

    public enum Menu {
        public static let glassPadding: CGFloat = Spacing.xs
        public static let panelWidth: CGFloat = 190
        public static let submenuWidth: CGFloat = 200
    }

    public enum ControlBar {
        public static let contentWidth: CGFloat = Layout.playerControlsContentWidth
        public static let buttonSpacing: CGFloat = Spacing.xl
        public static let paddingH: CGFloat = Spacing.xxl
        public static let paddingV: CGFloat = Spacing.sm
        public static let outerWidth: CGFloat = contentWidth + paddingH * 2
        public static let primaryFill: Color = .white.opacity(0.72)
        public static let primarySymbol: Color = .black.opacity(0.78)
    }

    public enum PlaybackEdge {
        public static let depth: CGFloat = 168
        public static let holdFraction: CGFloat = 0.25
    }

    public enum ProgressBar {
        public static let inactiveTrackHeight: CGFloat = (Interactive.mini - 4) * 0.5 * 0.75
        public static let trackHeight: CGFloat = (Interactive.mini - 4) * 0.5 * 1.25
        public static let thumbDiameter: CGFloat = trackHeight
        public static let inactiveScale: CGFloat = inactiveTrackHeight / trackHeight
        public static let thumbGrabWidth: CGFloat = Interactive.large
        public static let tapDragThreshold: CGFloat = 6
        public static let watchedEdgeHeight: CGFloat = 3
        public static let hitHeight: CGFloat = Interactive.regular
        public static let previewWidth: CGFloat = ControlBar.contentWidth
        public static let timeBubbleOffset: CGFloat = Spacing.xl
        public static let timeBubblePaddingH: CGFloat = Spacing.xs
        public static let timeBubblePaddingV: CGFloat = Spacing.xxs
        public static let timeBubbleRadius: CGFloat = Radius.small
        public static let thumbStroke: Color = .black.opacity(0.18)
        public static let thumbStrokeWidth: CGFloat = Stroke.regular
        public static let playedColor: Color = .white.opacity(0.72)
        public static let playedHoverColor: Color = .white.opacity(0.95)
    }

    public enum PrecisionTimeline {
        public static let expandedWidth: CGFloat = 1152
        public static let expandedHeight: CGFloat = 220
        public static let expansionGap: CGFloat = Spacing.lg
        public static let dismissMargin: CGFloat = Spacing.xxxl
        public static let panelPadding: CGFloat = Spacing.lg
        public static let headerHeight: CGFloat = 64
        public static let rulerHeight: CGFloat = 44
        public static let filmStripHeight: CGFloat = 72
        public static let sprocketWidth: CGFloat = Spacing.xs
        public static let sprocketHeight: CGFloat = Spacing.xxs
        public static let sprocketSpacing: CGFloat = Spacing.sm
        public static let filmImageInset: CGFloat = Spacing.sm
        public static let zoomRailWidth: CGFloat = 360
        public static let zoomRailHeight: CGFloat = 22.5
        public static let zoomRailThumbSize: CGFloat = 19.5
        public static let zoomButtonSize: CGFloat = Interactive.compact
        public static let frameButtonSize: CGFloat = Interactive.regular
        public static let frameButtonHitSize: CGFloat = Interactive.large
        public static let frameButtonCenterGap: CGFloat = Spacing.xxl
        public static let playheadWidth: CGFloat = 2
        public static let majorTickHeight: CGFloat = Spacing.lg
        public static let minorTickHeight: CGFloat = Spacing.xs
        public static let thumbnailSeparatorWidth: CGFloat = Stroke.subtle
        public static let thumbnailMinWidth: CGFloat = Interactive.large
        public static let thumbnailSecondsScale: CGFloat = Spacing.sm
        public static let majorTickTargetSpacing: CGFloat = 96
        public static let minorTickTargetSpacing: CGFloat = 18
        public static let minPixelsPerSecond: CGFloat = 0.04
        public static let maxPixelsPerSecond: CGFloat = 288
        public static let initialPixelsPerSecond: CGFloat = 2.4
        public static let zoomStepRatio: CGFloat = 1.28
        public static let previewDuration: Double = 8_894
        public static let previewFrameRate: Double = 24
        public static let collapsedScale: CGFloat = 0.72
        public static let timecodeColor: Color = .white.opacity(0.92)
        public static let secondaryTextColor: Color = .white.opacity(0.46)
        public static let minorTickColor: Color = .white.opacity(0.22)
        public static let majorTickColor: Color = .white.opacity(0.46)
        public static let playheadColor: Color = .white.opacity(0.95)
        public static let playheadAccent: Color = Theme.accent
        public static let viewportFill: Color = .white.opacity(0.025)
        public static let viewportRestingBrightness: Double = 0.06
        public static let viewportInnerShadow: Color = .black.opacity(0.09)
        public static let viewportInnerShadowWidth: CGFloat = 3
        public static let viewportInnerShadowRadius: CGFloat = 1.5
        public static let viewportInnerShadowOffsetY: CGFloat = 1
        public static let playheadShadow: Color = .black.opacity(0.5)
        public static let playheadShadowRadius: CGFloat = 0.5
        public static let playheadShadowOffsetX: CGFloat = 1.5
        public static let filmStripHighlight: Color = .white.opacity(0.092)
        public static let filmStripBase: Color = .black.opacity(0.38)
        public static let filmStripBand: Color = .black.opacity(0.472)
        public static let sprocketFill: Color = .black.opacity(0.648)
        public static let filmStripSeparator: Color = .black.opacity(0.348)
        public static let zoomRailFill: Color = .white.opacity(0.12)
        public static let zoomRailActiveFill: Color = Theme.accent.opacity(0.72)
        public static let thumbnailPalette: [Color] = [
            Color(red: 0.104, green: 0.244, blue: 0.324),
            Color(red: 0.228, green: 0.176, blue: 0.324),
            Color(red: 0.316, green: 0.208, blue: 0.128),
            Color(red: 0.148, green: 0.288, blue: 0.204),
            Color(red: 0.340, green: 0.274, blue: 0.128),
            Color(red: 0.192, green: 0.158, blue: 0.348)
        ]
    }
}
