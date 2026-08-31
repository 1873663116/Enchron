import DesignSystem
import Foundation
import SwiftUI

public struct FusedPlayerPanelLive {
    var presentation: PlaybackPresentation
    var mediaName: String
    var mediaProfile: PlaybackModel.MediaProfile?
    var canApplyFormat: Bool
    var screenScale: Double
    var recommendedScreenScale: Double
    var screenDistance: Double
    var screenElevationDegrees: Double
    var projection: PlaybackModel.ProjectionType
    var horizontalFieldOfViewDegrees: Int
    var stereoLayout: PlaybackModel.StereoLayout
    var usesDolbyVisionFallback: Bool = false
    var showsDolbyVisionFallback: Bool = false
    var mediaFormatSummary: String?
    var overview: String?
    var unmetCapabilities: [UnmetCapability] = []
    var mediaFormatProvenance: MediaFormatProvenance
    var sourceMediaFormatSummary: String
    var isPlaying: Bool
    var showsReplay: Bool
    var canSkipForward: Bool
    var canStepForward: Bool
    var progress: CGFloat
    var elapsedLabel: String
    var durationLabel: String
    var duration: Double
    var framesPerSecond: Double
    var onPlayPause: () -> Void
    var onSkipBackward: () -> Void
    var onSkipForward: () -> Void
    var onSeek: (CGFloat) -> Void
    var onPrecisionSeek: (CGFloat) -> Void
    var onFrameStep: (Int) -> Void
    var onEnterImmersive: () -> Void
    var onExitSpatial: () -> Void
    var onExitPlayback: () -> Void
    var onSetScreenScale: @MainActor @Sendable (Double) -> Void
    var onSetScreenDistance: @MainActor @Sendable (Double) -> Void
    var onSetScreenElevation: @MainActor @Sendable (Double) -> Void
    var onResetDockedPlacement: () -> Void
    var onApplyFormat: (
        PlaybackModel.ProjectionType,
        Int?,
        PlaybackModel.StereoLayout,
        Bool
    ) -> Void
    var onRestoreAutomaticFormat: () -> Void
    var onReachabilityAction: (String) -> Void = { _ in }
    var subtitlesEnabled: Bool = true
    var subtitleItems: [DeckMenuItem]
    var audioItems: [DeckMenuItem]
    var speedItems: [DeckMenuItem]
    var episodeItems: [DeckMenuItem]

    public init(
        presentation: PlaybackPresentation,
        mediaName: String,
        mediaProfile: PlaybackModel.MediaProfile?,
        canApplyFormat: Bool,
        screenScale: Double,
        recommendedScreenScale: Double,
        screenDistance: Double,
        screenElevationDegrees: Double,
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int,
        stereoLayout: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool = false,
        showsDolbyVisionFallback: Bool = false,
        mediaFormatSummary: String? = nil,
        overview: String? = nil,
        unmetCapabilities: [UnmetCapability] = [],
        mediaFormatProvenance: MediaFormatProvenance,
        sourceMediaFormatSummary: String,
        isPlaying: Bool,
        showsReplay: Bool,
        canSkipForward: Bool,
        canStepForward: Bool,
        progress: CGFloat,
        elapsedLabel: String,
        durationLabel: String,
        duration: Double,
        framesPerSecond: Double,
        onPlayPause: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void,
        onSkipForward: @escaping () -> Void,
        onSeek: @escaping (CGFloat) -> Void,
        onPrecisionSeek: @escaping (CGFloat) -> Void,
        onFrameStep: @escaping (Int) -> Void,
        onEnterImmersive: @escaping () -> Void,
        onExitSpatial: @escaping () -> Void,
        onExitPlayback: @escaping () -> Void,
        onSetScreenScale: @escaping @MainActor @Sendable (Double) -> Void,
        onSetScreenDistance: @escaping @MainActor @Sendable (Double) -> Void,
        onSetScreenElevation: @escaping @MainActor @Sendable (Double) -> Void,
        onResetDockedPlacement: @escaping () -> Void,
        onApplyFormat: @escaping ( PlaybackModel.ProjectionType, Int?, PlaybackModel.StereoLayout, Bool ) -> Void,
        onRestoreAutomaticFormat: @escaping () -> Void,
        onReachabilityAction: @escaping (String) -> Void = { _ in },
        subtitlesEnabled: Bool = true,
        subtitleItems: [DeckMenuItem],
        audioItems: [DeckMenuItem],
        speedItems: [DeckMenuItem],
        episodeItems: [DeckMenuItem]
    ) {
        self.presentation = presentation
        self.mediaName = mediaName
        self.mediaProfile = mediaProfile
        self.canApplyFormat = canApplyFormat
        self.screenScale = screenScale
        self.recommendedScreenScale = recommendedScreenScale
        self.screenDistance = screenDistance
        self.screenElevationDegrees = screenElevationDegrees
        self.projection = projection
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.stereoLayout = stereoLayout
        self.usesDolbyVisionFallback = usesDolbyVisionFallback
        self.showsDolbyVisionFallback = showsDolbyVisionFallback
        self.mediaFormatSummary = mediaFormatSummary
        self.overview = overview
        self.unmetCapabilities = unmetCapabilities
        self.mediaFormatProvenance = mediaFormatProvenance
        self.sourceMediaFormatSummary = sourceMediaFormatSummary
        self.isPlaying = isPlaying
        self.showsReplay = showsReplay
        self.canSkipForward = canSkipForward
        self.canStepForward = canStepForward
        self.progress = progress
        self.elapsedLabel = elapsedLabel
        self.durationLabel = durationLabel
        self.duration = duration
        self.framesPerSecond = framesPerSecond
        self.onPlayPause = onPlayPause
        self.onSkipBackward = onSkipBackward
        self.onSkipForward = onSkipForward
        self.onSeek = onSeek
        self.onPrecisionSeek = onPrecisionSeek
        self.onFrameStep = onFrameStep
        self.onEnterImmersive = onEnterImmersive
        self.onExitSpatial = onExitSpatial
        self.onExitPlayback = onExitPlayback
        self.onSetScreenScale = onSetScreenScale
        self.onSetScreenDistance = onSetScreenDistance
        self.onSetScreenElevation = onSetScreenElevation
        self.onResetDockedPlacement = onResetDockedPlacement
        self.onApplyFormat = onApplyFormat
        self.onRestoreAutomaticFormat = onRestoreAutomaticFormat
        self.onReachabilityAction = onReachabilityAction
        self.subtitlesEnabled = subtitlesEnabled
        self.subtitleItems = subtitleItems
        self.audioItems = audioItems
        self.speedItems = speedItems
        self.episodeItems = episodeItems
    }
}

enum PlaybackSeekPresentation {
    static let targetMatchTolerance: CGFloat = 0.02

    static func clampedTarget(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }

    static func target(
        at locationX: CGFloat,
        travelWidth: CGFloat,
        thumbDiameter: CGFloat
    ) -> CGFloat {
        guard travelWidth > 0 else { return 0 }
        let leadingThumbCenter = thumbDiameter / 2
        return clampedTarget((locationX - leadingThumbCenter) / travelWidth)
    }

    static func elapsedSeconds(
        for displayProgress: CGFloat,
        duration: Double
    ) -> Double? {
        guard displayProgress.isFinite,
              duration.isFinite,
              duration > 0 else {
            return nil
        }
        return Double(clampedTarget(displayProgress)) * duration
    }

    static func pendingTarget(
        for progress: CGFloat,
        livePositionAvailable: Bool
    ) -> CGFloat? {
        guard livePositionAvailable else { return nil }
        return clampedTarget(progress)
    }

    static func target(
        _ target: CGFloat,
        matches observedPosition: CGFloat?
    ) -> Bool {
        guard target.isFinite,
              let observedPosition,
              observedPosition.isFinite else {
            return false
        }
        return abs(observedPosition - target) <= targetMatchTolerance
    }

    static func displayProgress(
        isDragging: Bool,
        isTimelineDragging: Bool,
        localProgress: CGFloat,
        pendingTarget: CGFloat?,
        liveProgress: CGFloat?
    ) -> CGFloat {
        if isDragging || isTimelineDragging { return localProgress }
        if let pendingTarget { return pendingTarget }
        return liveProgress ?? localProgress
    }
}

private enum PlaybackControlPanelSurface {
    case windowOrnament
    case playerControlDock
}

enum PlaybackPanelSettingsPolicy {
    static func showsVideoFormatEditor(
        for presentation: PlaybackPresentation
    ) -> Bool {
        presentation.usesMainWindow
    }

    static func showsPlacementControls(
        for presentation: PlaybackPresentation
    ) -> Bool {
        presentation.usesMainWindow == false
            && presentation.contentFamily == .flat
    }

    static func settingsAreAvailable(
        for presentation: PlaybackPresentation
    ) -> Bool {
        showsVideoFormatEditor(for: presentation)
            || showsPlacementControls(for: presentation)
    }
}

public struct WindowPlaybackControls: View {
    let live: FusedPlayerPanelLive
    var onInteraction: () -> Void = {}
    var initialExpansion: PlaybackPanelExpansion.Layout = .collapsed
    var controlsVisible: Bool = true

    public var body: some View {
        FusedPlayerPanel(
            live: live,
            onInteraction: onInteraction,
            surface: .windowOrnament,
            initialExpansion: initialExpansion,
            controlsVisible: controlsVisible
        )
    }

    public init(
        live: FusedPlayerPanelLive,
        onInteraction: @escaping () -> Void = {},
        initialExpansion: PlaybackPanelExpansion.Layout = .collapsed,
        controlsVisible: Bool = true
    ) {
        self.live = live
        self.onInteraction = onInteraction
        self.initialExpansion = initialExpansion
        self.controlsVisible = controlsVisible
    }
}

public struct PlayerControlDock: View {
    let live: FusedPlayerPanelLive
    var onInteraction: () -> Void = {}
    var initialExpansion: PlaybackPanelExpansion.Layout = .collapsed
    var controlsVisible: Bool = true

    public var body: some View {
        FusedPlayerPanel(
            live: live,
            onInteraction: onInteraction,
            surface: .playerControlDock,
            initialExpansion: initialExpansion,
            controlsVisible: controlsVisible
        )
    }

    public init(
        live: FusedPlayerPanelLive,
        onInteraction: @escaping () -> Void = {},
        initialExpansion: PlaybackPanelExpansion.Layout = .collapsed,
        controlsVisible: Bool = true
    ) {
        self.live = live
        self.onInteraction = onInteraction
        self.initialExpansion = initialExpansion
        self.controlsVisible = controlsVisible
    }
}

public struct FusedPlayerPanel: View {
    var live: FusedPlayerPanelLive?
    var onInteraction: () -> Void = {}
    private let surface: PlaybackControlPanelSurface

    public init(
        live: FusedPlayerPanelLive? = nil,
        onInteraction: @escaping () -> Void = {},
        initialExpansion: PlaybackPanelExpansion.Layout = .collapsed,
        controlsVisible: Bool = true
    ) {
        let presentation = live?.presentation ?? .window
        let resolvedSurface: PlaybackControlPanelSurface = (
            presentation.usesMainWindow
                ? .windowOrnament
                : .playerControlDock
        )
        self.live = live
        self.onInteraction = onInteraction
        self.surface = resolvedSurface
        self.controlsVisible = controlsVisible
        _expansion = State(
            initialValue: PlaybackPanelExpansion(
                Self.resolvedInitialLayout(initialExpansion, presentation: presentation)
            )
        )
        _videoFormatEditing = State(
            initialValue: PlaybackVideoFormatEditingState(
                projection: live?.projection ?? .flat,
                horizontalFieldOfViewDegrees: live?.horizontalFieldOfViewDegrees
                    ?? PanoramaHorizontalCoverage.defaultCustomAngle,
                stereoLayout: live?.stereoLayout ?? .mono,
                usesDolbyVisionFallback: live?.usesDolbyVisionFallback ?? false,
                beginsEditing: initialExpansion == .settings
                    && resolvedSurface == .playerControlDock
                    && PlaybackPanelSettingsPolicy.showsVideoFormatEditor(
                        for: presentation
                    )
            )
        )
    }

    fileprivate init(
        live: FusedPlayerPanelLive,
        onInteraction: @escaping () -> Void,
        surface: PlaybackControlPanelSurface,
        initialExpansion: PlaybackPanelExpansion.Layout,
        controlsVisible: Bool = true
    ) {
        self.live = live
        self.onInteraction = onInteraction
        self.surface = surface
        self.controlsVisible = controlsVisible
        _expansion = State(
            initialValue: PlaybackPanelExpansion(
                Self.resolvedInitialLayout(
                    initialExpansion,
                    presentation: live.presentation
                )
            )
        )
        _videoFormatEditing = State(
            initialValue: PlaybackVideoFormatEditingState(
                projection: live.projection,
                horizontalFieldOfViewDegrees: live.horizontalFieldOfViewDegrees,
                stereoLayout: live.stereoLayout,
                usesDolbyVisionFallback: live.usesDolbyVisionFallback,
                beginsEditing: initialExpansion == .settings
                    && surface == .playerControlDock
                    && PlaybackPanelSettingsPolicy.showsVideoFormatEditor(
                        for: live.presentation
                    )
            )
        )
    }

    private static func resolvedInitialLayout(
        _ requested: PlaybackPanelExpansion.Layout,
        presentation: PlaybackPresentation
    ) -> PlaybackPanelExpansion.Layout {
        guard requested == .settings else { return requested }
        return PlaybackPanelSettingsPolicy.settingsAreAvailable(for: presentation)
            ? .settings
            : .collapsed
    }

    private let controlsVisible: Bool
    @State private var expansion: PlaybackPanelExpansion
    @State private var videoFormatEditing: PlaybackVideoFormatEditingState
    @State private var mediaInfoHovered = false

    @State private var progress: CGFloat = 0.45
    @State private var isDragging = false
    @State private var isTimelineDragging = false
    @State private var isProgressHovered = false
    @State private var scrubberActivation: ScrubberActivation = .idle
    @State private var seekOrigin: CGPoint?
    @State private var dragStartProgress: CGFloat = 0.45
    @State private var pendingSeekTarget: CGFloat?
    @State private var scrubFeedbackTrigger = 0
    @State private var scrubReleaseTrigger = 0
    @State private var scrubBoundary: EnchronScrubBoundary = .none
    @State private var timelineFeedbackTrigger = 0
    @State private var rewindIconAnimationTrigger = 0
    @State private var forwardIconAnimationTrigger = 0
    @State private var pixelsPerSecond: CGFloat = DesignTokens.PrecisionTimeline.initialPixelsPerSecond
    @State private var selectedSpeed = "1×"
    @State private var placementTrackWidth: CGFloat = 280
    @Namespace private var hoverNamespace

    private enum ScrubberActivation: Equatable {
        case idle
        case seeking
    }

    private var displayProgress: CGFloat {
        PlaybackSeekPresentation.displayProgress(
            isDragging: isDragging,
            isTimelineDragging: isTimelineDragging,
            localProgress: progress,
            pendingTarget: pendingSeekTarget,
            liveProgress: live?.progress
        )
    }

    private var displayedElapsedLabel: String {
        guard let live,
              let elapsedSeconds = PlaybackSeekPresentation.elapsedSeconds(
                  for: displayProgress,
                  duration: live.duration
              ) else {
            return live?.elapsedLabel ?? "6:21"
        }
        return PlaybackTimeFormatter.clock(elapsedSeconds)
    }

    private var clusterWidth: CGFloat {
        expansion.isExpanded
            ? DesignTokens.Layout.expandedPlayerControlsContentWidth
            : DesignTokens.ControlBar.contentWidth
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
    }

    public var body: some View {
        Group {
            panelContent
        }
        .opacity(expansion.contentIsVisible ? 1 : 0)
        .allowsHitTesting(expansion.contentIsVisible)
        .frame(width: clusterWidth)
        .padding(.horizontal, DesignTokens.ControlBar.paddingH)
        .padding(.vertical, DesignTokens.ControlBar.paddingV)
        .clipShape(shape)
        .enchronGlassBackground(in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-controls")
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest,
                  let live else {
                return
            }
            handleDebugMenuSelection(request, live: live)
        }
#endif
        .enchronScrubSensoryFeedback(
            pressTrigger: scrubFeedbackTrigger,
            releaseTrigger: scrubReleaseTrigger,
            boundary: scrubBoundary,
            boundariesEnabled: isDragging
        )
        .enchronPressSensoryFeedback(.selectionOn, trigger: timelineFeedbackTrigger)
        .onChange(of: displayProgress) { _, newValue in
            if !isDragging && !isTimelineDragging {
                scrubBoundary = EnchronScrubBoundary.from(normalized: Double(newValue))
            }
        }
        .onChange(of: live?.progress) { _, newValue in
            guard let target = pendingSeekTarget, let newValue else { return }
            if PlaybackSeekPresentation.target(target, matches: newValue) {
                pendingSeekTarget = nil
            }
        }
        .onChange(of: committedVideoFormatSelection) { _, selection in
            guard let selection else { return }
            videoFormatEditing.synchronizeCommittedVideoFormat(selection)
        }
        .onChange(of: controlsVisible) { _, isVisible in
            guard isVisible == false else { return }
            expansion = PlaybackPanelExpansion()
            videoFormatEditing.discard()
            isDragging = false
            isTimelineDragging = false
            scrubberActivation = .idle
            seekOrigin = nil
            pendingSeekTarget = nil
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        if expansion.layout == .mediaInformation {
            expandedMediaInformation
        } else {
            switch surface {
            case .windowOrnament:
                windowOrnamentContent
            case .playerControlDock:
                playerControlDockContent
            }
        }
    }

    private var windowOrnamentContent: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            if expansion.layout == .timeline {
                timelineBlock
            } else {
                progressBar(width: compactProgressBarWidth)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                windowTransportControls
                mediaInformationWell(width: windowMediaInformationWidth)
            }
        }
    }

    private var playerControlDockContent: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            mediaInformationWell(width: clusterWidth)
            playerControlDockControls

            if expansion.layout == .settings, let live {
                if PlaybackPanelSettingsPolicy.showsPlacementControls(
                    for: live.presentation
                ) {
                    dockedPlacementControls(live)
                } else if PlaybackPanelSettingsPolicy.showsVideoFormatEditor(
                    for: live.presentation
                ) {
                    videoFormatEditor(live)
                }
            }

            if expansion.layout == .timeline {
                timelineBlock
            } else {
                progressBar(width: compactProgressBarWidth)
            }
        }
    }

    private var windowMediaInformationWidth: CGFloat {
        clusterWidth
            - DesignTokens.Interactive.large * 3
            - DesignTokens.ControlBar.buttonSpacing * 2
            - DesignTokens.Spacing.sm
    }

    private var compactProgressBarWidth: CGFloat {
        clusterWidth
    }

    private func dockedPlacementControls(_ live: FusedPlayerPanelLive) -> some View {
        let titleWidth: CGFloat = 100
        let readoutWidth: CGFloat = 64
        let rowSpacing = DesignTokens.Spacing.md

        return VStack(spacing: DesignTokens.Spacing.sm) {
            DockedPlacementSliderRow(
                title: "Screen Size",
                liveValue: live.screenScale,
                range: PlaybackScreenSize.scaleRange,
                step: PlaybackScreenSize.scaleStep,
                trackWidth: placementTrackWidth,
                valueLabel: { "\(Int(($0 * 100).rounded()))%" },
                identifier: "ScreenSize",
                onChange: { value in
                    onInteraction()
                    live.onReachabilityAction("slider.ScreenSize")
                    live.onSetScreenScale(value)
                }
            )
            DockedPlacementSliderRow(
                title: "Distance",
                liveValue: live.screenDistance,
                range: PlaybackDockedPlacement.distanceRange,
                step: PlaybackDockedPlacement.distanceStep,
                trackWidth: placementTrackWidth,
                valueLabel: { String(format: "%.1f m", $0) },
                identifier: "Distance",
                onChange: { value in
                    onInteraction()
                    live.onReachabilityAction("slider.Distance")
                    live.onSetScreenDistance(value)
                }
            )
            DockedPlacementSliderRow(
                title: "Elevation",
                liveValue: live.screenElevationDegrees,
                range: PlaybackDockedPlacement.elevationRange,
                step: PlaybackDockedPlacement.elevationStep,
                trackWidth: placementTrackWidth,
                valueLabel: { "\(Int($0.rounded()))°" },
                identifier: "Elevation",
                onChange: { value in
                    onInteraction()
                    live.onReachabilityAction("slider.Elevation")
                    live.onSetScreenElevation(value)
                }
            )
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    onInteraction()
                    live.onReachabilityAction("dockedPlacement.reset")
                    live.onResetDockedPlacement()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("PlayerPanel-DockedPlacement-reset")
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        placementTrackWidth = max(
                            proxy.size.width - titleWidth - readoutWidth - rowSpacing * 2,
                            160
                        )
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        placementTrackWidth = max(
                            width - titleWidth - readoutWidth - rowSpacing * 2,
                            160
                        )
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-DockedPlacement")
    }

    private func videoFormatEditor(_ live: FusedPlayerPanelLive) -> some View {
        PlaybackVideoFormatEditor(
            projection: $videoFormatEditing.projection,
            horizontalFieldOfViewDegrees: $videoFormatEditing.horizontalFieldOfViewDegrees,
            stereoLayout: $videoFormatEditing.stereoLayout,
            usesDolbyVisionFallback: $videoFormatEditing.usesDolbyVisionFallback,
            canApplyFormat: live.canApplyFormat,
            mediaFormatProvenance: live.mediaFormatProvenance,
            sourceMediaFormatSummary: live.sourceMediaFormatSummary,
            showsDolbyVisionFallback: live.showsDolbyVisionFallback,
            identifierPrefix: "PlayerPanel-VideoFormat",
            onCancel: cancelVideoFormatEditing,
            onApply: applyVideoFormatEditing,
            onRestoreAutomaticFormat: restoreAutomaticFormat,
            onReachabilityAction: { action in
                live.onReachabilityAction("videoFormat.\(action)")
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-VideoFormat")
    }

    private var committedVideoFormatSelection: PlaybackVideoFormatSelection? {
        guard let live else { return nil }
        return PlaybackVideoFormatSelection(
            projection: live.projection,
            horizontalFieldOfViewDegrees: live.projection == .customAngle
                ? live.horizontalFieldOfViewDegrees
                : nil,
            stereoLayout: live.stereoLayout,
            usesDolbyVisionFallback: live.usesDolbyVisionFallback
        )
    }

    private func cancelVideoFormatEditing() {
        videoFormatEditing.discard()
        collapseSettings()
        onInteraction()
    }

    private func applyVideoFormatEditing() {
        guard let live,
              let selection = videoFormatEditing.commit() else { return }
        if let committedVideoFormatSelection {
            videoFormatEditing.synchronizeCommittedVideoFormat(
                committedVideoFormatSelection
            )
        }
        collapseSettings()
        onInteraction()
        live.onApplyFormat(
            selection.projection,
            selection.horizontalFieldOfViewDegrees,
            selection.stereoLayout,
            selection.usesDolbyVisionFallback
        )
    }

    private func restoreAutomaticFormat() {
        guard let live else { return }
        videoFormatEditing.discard()
        collapseSettings()
        onInteraction()
        live.onRestoreAutomaticFormat()
    }

    private func collapseSettings() {
        changeExpansion(to: .collapsed)
    }

    private func changeExpansion(to layout: PlaybackPanelExpansion.Layout) {
        withAnimation(DesignTokens.AnimationToken.panelContentExit) {
            expansion.request(layout)
        } completion: {
            advanceExpansion(from: .contentLeaving)
        }
    }

    private func advanceExpansion(from completed: PlaybackPanelExpansion.Phase) {
        let animation = completed == .contentLeaving
            ? DesignTokens.AnimationToken.panelSpring
            : DesignTokens.AnimationToken.panelContentEntrance
        withAnimation(animation) {
            expansion.advance(from: completed)
        } completion: {
            guard completed == .contentLeaving else { return }
            advanceExpansion(from: .resizing)
        }
    }

    private var windowTransportControls: some View {
        HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
            windowRewindButton
            windowPlayButton
            windowForwardButton
        }
    }

    @ViewBuilder
    private var playerControlDockControls: some View {
        if let live {
            ZStack {
                HStack(spacing: 0) {
                    HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                        if PlaybackPanelSettingsPolicy.settingsAreAvailable(
                            for: live.presentation
                        ) {
                            GlassCircleIconButton.settings(
                                isExpanded: expansion.isShowing(.settings),
                                accessibilityLabel: expansion.isShowing(.settings) ? "Close Advanced Settings" : "Open Advanced Settings",
                                action: toggleSettings,
                                accessibilityIdentifier: "PlayerPanel-button-settings"
                            )
                        }
                        returnToWindowButton(live)
                    }

                    Spacer(minLength: 0)

                    moreMenu
                }

                HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                    rewindButton
                    playButton
                    forwardButton
                }
            }
            .frame(width: clusterWidth, height: DesignTokens.Interactive.large)
        }
    }

    private func mediaInformationWell(width: CGFloat) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.element,
            style: .continuous
        )
        return ZStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(live?.mediaName ?? "Unknown")
                    .font(DesignTokens.Typography.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if persistentCapabilities.isEmpty == false {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .enchronHoverOffset(
                activeY: -DesignTokens.Spacing.sm,
                in: mediaInfoHoverRevealGroup,
                forcedActive: mediaInfoHovered,
                animation: DesignTokens.AnimationToken.informationReveal
            )

            PlaybackMediaMetadataRow(
                spatialMetadataLabel: spatialMetadataLabel,
                technicalMetadataLabel: technicalMetadataLabel
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .enchronHoverOffset(
                activeY: 0,
                inactiveY: DesignTokens.Spacing.xxs,
                in: mediaInfoHoverRevealGroup,
                forcedActive: mediaInfoHovered,
                animation: DesignTokens.AnimationToken.informationReveal
            )
            .enchronHoverOpacity(
                active: 1,
                inactive: 0,
                in: mediaInfoHoverRevealGroup,
                forcedActive: mediaInfoHovered,
                animation: DesignTokens.AnimationToken.informationReveal
            )
        }
        .frame(width: width, height: DesignTokens.Layout.playbackMediaInfoHeight)
        .background(.thickMaterial, in: shape)
        .overlay {
            shape.stroke(.white.opacity(0.08), lineWidth: DesignTokens.Stroke.subtle)
        }
        .contentShape(.interaction, shape)
        .enchronHoverContentShape(shape)
        .enchronHoverActivation(in: mediaInfoHoverActivationGroup)
        .onHover { hovering in
            withAnimation(DesignTokens.AnimationToken.informationReveal) {
                mediaInfoHovered = hovering
            }
        }
        .onTapGesture {
            toggleMediaInformation()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(live?.mediaName ?? "Unknown media")
        .accessibilityValue(mediaInformationAccessibilityValue)
        .accessibilityIdentifier("PlayerPanel-media-information")
    }

    private var persistentCapabilities: [UnmetCapability] {
        (live?.unmetCapabilities ?? []).filter { $0.preventsPlayback == false }
    }

    private var mediaInformationIsExpandable: Bool {
        live != nil
    }

    private var mediaInformationAccessibilityValue: String {
        var parts = ["\(spatialMetadataLabel), \(technicalMetadataLabel)"]
        parts.append(contentsOf: persistentCapabilities.map(\.summary))
        return parts.joined(separator: ". ")
    }

    private var expandedMediaInformation: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    Text(live?.mediaName ?? "Unknown")
                        .font(DesignTokens.Typography.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    if let overview = live?.overview, overview.isEmpty == false {
                        Text(overview)
                            .font(DesignTokens.Typography.metadata)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("PlayerPanel-media-information-overview")
                    }

                    ForEach(persistentCapabilities) { capability in
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                            Label(
                                "\(capability.requested). \(capability.delivered).",
                                systemImage: "exclamationmark.circle"
                            )
                            .font(DesignTokens.Typography.metadata)
                            Text(capability.reason)
                                .font(DesignTokens.Typography.metadata)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier(
                            "PlayerPanel-media-information-unmet-\(capability.id)"
                        )
                    }

                    HStack(spacing: DesignTokens.Spacing.xl) {
                        Text(spatialMetadataLabel)
                        Text(technicalMetadataLabel)
                    }
                    .font(DesignTokens.Typography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.xl)
                .padding(.trailing, DesignTokens.Interactive.large)
            }

            GlassCircleIconButton.close(
                accessibilityLabel: "Close Media Information",
                action: toggleMediaInformation,
                accessibilityIdentifier: "PlayerPanel-media-information-close"
            )
            .keyboardShortcut(.escape, modifiers: [])
            .padding(DesignTokens.Spacing.xl)
        }
        .frame(width: clusterWidth, height: 420)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-media-information-expanded")
    }

    private func toggleMediaInformation() {
        if expansion.isShowing(.mediaInformation) {
            changeExpansion(to: .collapsed)
            live?.onReachabilityAction("mediaInformation.close")
        } else {
            guard mediaInformationIsExpandable else { return }
            changeExpansion(to: .mediaInformation)
            live?.onReachabilityAction("mediaInformation.open")
        }
        onInteraction()
    }

    private var mediaInfoHoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "media-information", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var mediaInfoHoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "media-information", in: hoverNamespace, behavior: .followsGroup)
    }

    private var spatialMetadataLabel: String {
        guard let live else { return "Flat · Mono" }
        if let mediaFormatSummary = live.mediaFormatSummary {
            return mediaFormatSummary
        }
        return "\(projectionLabel(live.projection)) · \(stereoLabel(live.stereoLayout))"
    }

    private var technicalMetadataLabel: String {
        guard let profile = live?.mediaProfile else { return "Media information unavailable" }
        var parts = ["\(profile.resolution.width)×\(profile.resolution.height)"]
        parts.append(PlaybackInfoFormatter.dynamicRangeLabel(profile))
        let codec = PlaybackInfoFormatter.videoCodecLabel(profile.videoCodec)
        if codec != "Unknown" { parts.append(codec) }
        if profile.frameRate > 0 { parts.append(PlaybackInfoFormatter.frameRate(profile.frameRate)) }
        return parts.joined(separator: " · ")
    }

    private func projectionLabel(_ projection: PlaybackModel.ProjectionType) -> String {
        switch projection {
        case .flat: "Flat"
        case .equirectangular180: "180°"
        case .equirectangular360: "360°"
        case .customAngle: "Custom Angle"
        }
    }

    private func stereoLabel(_ stereo: PlaybackModel.StereoLayout) -> String {
        switch stereo {
        case .mono: "Mono"
        case .multiview: "Native Multiview"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }

    @ViewBuilder
    private func returnToWindowButton(_ live: FusedPlayerPanelLive) -> some View {
        if live.presentation == .panorama {
            GlassCircleIconButton.collapseVertically(
                accessibilityLabel: "Return to Portal",
                action: live.onExitSpatial,
                accessibilityIdentifier: "PlayerPanel-button-exit-spatial"
            )
            .keyboardShortcut(.escape, modifiers: [])
        } else if live.presentation == .docked {
            GlassCircleIconButton.collapse(
                accessibilityLabel: "Return to Window",
                action: live.onExitSpatial,
                accessibilityIdentifier: "PlayerPanel-button-exit-spatial"
            )
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var windowRewindButton: some View {
        seekButton(
            direction: .backward,
            compactSystemName: "gobackward.15",
            expandedSystemName: "backward.frame",
            accessibilityLabel: expansion.layout == .timeline ? "Previous frame" : "Rewind 15 seconds",
            action: performBackwardAction,
            animationTrigger: rewindIconAnimationTrigger,
            visualSize: DesignTokens.Interactive.regular,
            targetSize: DesignTokens.Interactive.large,
            iconTier: .standard
        )
        .keyboardShortcut(.leftArrow, modifiers: [])
    }

    private var windowForwardButton: some View {
        seekButton(
            direction: .forward,
            compactSystemName: "goforward.15",
            expandedSystemName: "forward.frame",
            accessibilityLabel: expansion.layout == .timeline ? "Next frame" : "Forward 15 seconds",
            action: performForwardAction,
            animationTrigger: forwardIconAnimationTrigger,
            visualSize: DesignTokens.Interactive.regular,
            targetSize: DesignTokens.Interactive.large,
            iconTier: .standard
        )
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(
            expansion.layout == .timeline
                ? live?.canStepForward == false
                : live?.canSkipForward == false
        )
    }

    private var windowPlayButton: some View {
        GlassCircleIconButton(
            systemName: primaryPlayIcon,
            accessibilityLabel: primaryPlayLabel,
            action: { live?.onPlayPause() },
            accessibilityIdentifier: "PlayerPanel-button-play",
            visualSize: DesignTokens.Interactive.regular,
            targetSize: DesignTokens.Interactive.large,
            iconTier: .standard
        )
        .keyboardShortcut(.space, modifiers: [])
    }

    private var rewindButton: some View {
        seekButton(
            direction: .backward,
            compactSystemName: "gobackward.15",
            expandedSystemName: "backward.frame",
            accessibilityLabel: expansion.layout == .timeline ? "Previous frame" : "Rewind 15 seconds",
            action: performBackwardAction,
            animationTrigger: rewindIconAnimationTrigger
        )
        .keyboardShortcut(.leftArrow, modifiers: [])
    }

    private var forwardButton: some View {
        seekButton(
            direction: .forward,
            compactSystemName: "goforward.15",
            expandedSystemName: "forward.frame",
            accessibilityLabel: expansion.layout == .timeline ? "Next frame" : "Forward 15 seconds",
            action: performForwardAction,
            animationTrigger: forwardIconAnimationTrigger
        )
        .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(
                expansion.layout == .timeline
                    ? live?.canStepForward == false
                    : live?.canSkipForward == false
            )
    }

    @ViewBuilder
    private func seekButton(
        direction: DirectionalIconDirection,
        compactSystemName: String,
        expandedSystemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        animationTrigger: Int,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        targetSize: CGFloat = DesignTokens.Interactive.large,
        iconTier: ButtonIconTier = .standard
    ) -> some View {
        if expansion.layout == .timeline {
            GlassCircleIconButton(
                systemName: expandedSystemName,
                accessibilityLabel: accessibilityLabel,
                action: action,
                accessibilityIdentifier: direction == .backward
                    ? "PlayerPanel-button-rewind"
                    : "PlayerPanel-button-forward",
                visualSize: visualSize,
                targetSize: targetSize,
                iconTier: iconTier
            )
        } else {
            AnimatedDirectionalIconButton(
                systemName: compactSystemName,
                direction: direction,
                trigger: animationTrigger,
                accessibilityLabel: accessibilityLabel,
                action: action,
                accessibilityIdentifier: direction == .backward
                    ? "PlayerPanel-button-rewind"
                    : "PlayerPanel-button-forward",
                visualSize: visualSize,
                targetSize: targetSize,
                iconTier: iconTier
            )
        }
    }

    private func performBackwardAction() {
        if expansion.layout == .timeline {
            stepFrame(-1)
        } else {
            rewindIconAnimationTrigger &+= 1
            live?.onSkipBackward()
        }
    }

    private func performForwardAction() {
        if expansion.layout == .timeline {
            stepFrame(1)
        } else {
            forwardIconAnimationTrigger &+= 1
            live?.onSkipForward()
        }
    }

    private var moreMenu: some View {
        GlassCircleIconMenu(
            systemName: "ellipsis",
            accessibilityLabel: "More",
            accessibilityIdentifier: "PlayerPanel-menu-more"
        ) {
            if let live {
                liveMoreMenuSections(live)
            } else {
                mockMoreMenuSections
            }
        }
        .accessibilityLabel("More playback settings")
    }

    private func stepFrame(_ direction: Double) {
        if let live {
            live.onFrameStep(direction < 0 ? -1 : 1)
            return
        }
        let fps = DesignTokens.PrecisionTimeline.previewFrameRate
        let duration = DesignTokens.PrecisionTimeline.previewDuration
        guard fps > 0, duration > 0 else { return }
        let frameDuration = 1 / fps
        let currentTime = Double(progress) * duration
        let nextTime = min(max(currentTime + direction * frameDuration, 0), duration)
        progress = CGFloat(nextTime / duration)
    }

    private var playButton: some View {
        GlassCircleIconButton(
            systemName: primaryPlayIcon,
            accessibilityLabel: primaryPlayLabel,
            action: { live?.onPlayPause() },
            accessibilityIdentifier: "PlayerPanel-button-play",
            visualSize: DesignTokens.Interactive.regular,
            targetSize: DesignTokens.Interactive.large,
            iconTier: .standard
        )
        .keyboardShortcut(.space, modifiers: [])
    }

    private var primaryPlayIcon: String {
        guard let live else { return "play.fill" }
        if live.showsReplay { return "arrow.counterclockwise" }
        return live.isPlaying ? "pause.fill" : "play.fill"
    }

    private var primaryPlayLabel: String {
        guard let live else { return "Play" }
        if live.showsReplay { return "Replay" }
        return live.isPlaying ? "Pause" : "Play"
    }

    @ViewBuilder
    private var mockMoreMenuSections: some View {
        Section("Playback Settings") {
            mockSelectableMenu(
                "Playback Speed",
                ["0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×", "3×", "5×"],
                selection: $selectedSpeed
            )
            Menu("Episodes") {
                menuOption("Episode 1 · The Signal")
                menuOption("Episode 2 · Evening Crossing")
                menuOption("Episode 3 · Glass Harbor")
                menuOption("Episode 4 · Quiet Orbit")
                menuOption("Episode 5 · Afterimage")
                menuOption("Episode 6 · The Long Return")
            }
        }
    }

    @ViewBuilder
    private func liveMoreMenuSections(_ live: FusedPlayerPanelLive) -> some View {
        Group {
            if !live.subtitleItems.isEmpty {
                Menu("Subtitles") {
                    liveMenuItems(live.subtitleItems, category: "subtitle")
                }
                .accessibilityIdentifier("PlayerPanel-menu-subtitles")
                .disabled(!live.subtitlesEnabled)
            }
            if !live.audioItems.isEmpty {
                Menu("Audio Track") {
                    liveMenuItems(live.audioItems, category: "audio")
                }
                .accessibilityIdentifier("PlayerPanel-menu-audio")
            }
            Menu("Playback Speed") {
                liveMenuItems(live.speedItems, category: "speed")
            }
            .accessibilityIdentifier("PlayerPanel-menu-speed")
            if !live.episodeItems.isEmpty {
                Menu("Episodes") {
                    liveMenuItems(live.episodeItems, category: "episode")
                }
                .accessibilityIdentifier("PlayerPanel-menu-episodes")
            }
        }
        .onAppear {
            live.onReachabilityAction("menu.more")
        }
    }

    @ViewBuilder
    private func liveMenuItems(
        _ items: [DeckMenuItem],
        category: String
    ) -> some View {
        ForEach(items) { item in
            Button {
                guard let live else { return }
                activateMenuItem(item, live: live)
            } label: {
                if item.isSelected {
                    Label(item.title, systemImage: "checkmark")
                } else {
                    Text(item.title)
                }
            }
            .accessibilityIdentifier("PlayerPanel-menu-\(category)-\(item.id)")
        }
        .onAppear {
            live?.onReachabilityAction("menu.\(category)")
        }
    }

    private func activateMenuItem(
        _ item: DeckMenuItem,
        live: FusedPlayerPanelLive
    ) {
        live.onReachabilityAction("menu.item.\(item.id)")
        item.action()
    }

#if DEBUG
    private func handleDebugMenuSelection(
        _ request: DebugMenuSelectionRequest,
        live: FusedPlayerPanelLive
    ) {
        let items: [DeckMenuItem]
        switch request.family {
        case .subtitles:
            items = live.subtitleItems
        case .audio:
            items = live.audioItems
        case .speed:
            items = live.speedItems
        case .episodes:
            items = live.episodeItems
        default:
            return
        }
        request.handle(
            host: .playerPanel,
            family: request.family,
            items: items.map { item in
                DebugMenuSelectionItem(
                    id: item.id,
                    title: item.title,
                    isSelected: item.isSelected,
                    select: { activateMenuItem(item, live: live) }
                )
            }
        )
    }
#endif

    private func menuOption(_ title: String) -> some View {
        Button {} label: { Text(title) }
    }

    private func mockSelectableMenu(
        _ title: String,
        _ options: [String],
        selection: Binding<String>
    ) -> some View {
        Menu(title) {
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var timelineBlock: some View {
        PrecisionTimelineView(
            currentTime: timelineCurrentTime,
            pixelsPerSecond: $pixelsPerSecond,
            duration: timelineDuration,
            framesPerSecond: timelineFramesPerSecond,
            onSeekBegan: beginTimelineSeek,
            onSeekEnded: commitTimelineSeek
        )
        .frame(
            width: clusterWidth,
            height: DesignTokens.PrecisionTimeline.expandedHeight
        )
        .transition(.opacity)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { closeTimeline() })
    }

    private var timelineCurrentTime: Binding<Double> {
        Binding(
            get: { Double(displayProgress) * timelineDuration },
            set: { newValue in
                progress = timelineDuration > 0 ? CGFloat(newValue / timelineDuration) : 0
            }
        )
    }

    private var timelineDuration: Double {
        guard let duration = live?.duration, duration > 0 else {
            return DesignTokens.PrecisionTimeline.previewDuration
        }
        return duration
    }

    private var timelineFramesPerSecond: Double {
        guard let framesPerSecond = live?.framesPerSecond, framesPerSecond > 0 else {
            return DesignTokens.PrecisionTimeline.previewFrameRate
        }
        return framesPerSecond
    }

    private func commitTimelineSeek(_ seconds: Double) {
        guard timelineDuration > 0 else {
            isTimelineDragging = false
            return
        }
        let target = PlaybackSeekPresentation.clampedTarget(
            CGFloat(seconds / timelineDuration)
        )
        progress = target
        armPendingSeek(for: target)
        isTimelineDragging = false
        live?.onPrecisionSeek(target)
    }

    private func beginTimelineSeek() {
        progress = displayProgress
        isTimelineDragging = true
        onInteraction()
    }

    private var trackScale: CGFloat {
        if isDragging || isProgressHovered { return 1 }
        switch scrubberActivation {
        case .seeking:
            return 1
        case .idle:
            return DesignTokens.ProgressBar.inactiveScale
        }
    }

    private var hoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "fused-progress-reveal", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var hoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "fused-progress-reveal", in: hoverNamespace, behavior: .followsGroup)
    }

    private func progressBar(width overlayWidth: CGFloat) -> some View {
        let width = max(overlayWidth - DesignTokens.ProgressBar.thumbDiameter, 0)
        let clampedProgress = min(max(displayProgress, 0), 1)
        let thumbX = DesignTokens.ProgressBar.thumbDiameter / 2 + clampedProgress * width
        return progressBarBody(
            width: width,
            clampedProgress: clampedProgress,
            thumbX: thumbX,
            overlayWidth: overlayWidth
        )
        .transition(.opacity)
    }

    private func progressBarBody(
        width: CGFloat,
        clampedProgress: CGFloat,
        thumbX: CGFloat,
        overlayWidth: CGFloat
    ) -> some View {
        return ZStack(alignment: .leading) {
            progressHub(
                width: width,
                progress: clampedProgress,
                overlayWidth: overlayWidth,
                scale: trackScale
            )

            timeBubble
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2 + DesignTokens.ProgressBar.timeBubbleOffset
                )
                .enchronHoverOpacity(
                    active: 1,
                    inactive: 0,
                    in: hoverRevealGroup,
                    forcedActive: isDragging || isProgressHovered,
                    animation: DesignTokens.AnimationToken.selection
                )
                .allowsHitTesting(false)

            scrubberControl(width: width)
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2
                )
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .enchronHoverContentShape(Capsule())
        .enchronHoverActivation(in: hoverActivationGroup)
        .contentShape(.interaction, Capsule())
        .onHover { isProgressHovered = $0 }
        .gesture(
            ExclusiveGesture(
                SpatialTapGesture(count: 2),
                SpatialTapGesture()
            ).onEnded { value in
                switch value {
                case .first:
                    openTimeline()
                case .second(let tap):
                    seekToTrack(at: tap.location.x, travelWidth: width)
                }
            }
        )
        .simultaneousGesture(
            dragGesture(width: width, thumbX: thumbX)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-progress")
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(displayedElapsedLabel) of \(live?.durationLabel ?? "14:15")")
        .accessibilityAdjustableAction { direction in
            adjustProgressForAccessibility(direction)
        }
    }

    private func progressHub(
        width: CGFloat,
        progress: CGFloat,
        overlayWidth: CGFloat,
        scale: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                progressTrackLayer(
                    railWidth: overlayWidth,
                    playedWidth: DesignTokens.ProgressBar.thumbDiameter / 2 + width * progress,
                    scale: scale,
                    playedColor: DesignTokens.ProgressBar.playedColor
                )

                progressTrackLayer(
                    railWidth: overlayWidth,
                    playedWidth: DesignTokens.ProgressBar.thumbDiameter / 2 + width * progress,
                    scale: scale,
                    playedColor: DesignTokens.ProgressBar.playedHoverColor
                )
                .enchronHoverOpacity(
                    active: 1,
                    inactive: 0,
                    in: hoverRevealGroup,
                    forcedActive: isDragging || isProgressHovered,
                    animation: DesignTokens.AnimationToken.selection
                )
            }
            .frame(width: overlayWidth, height: DesignTokens.ProgressBar.trackHeight)
            .scaleEffect(y: scale)
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .allowsHitTesting(false)
    }

    private func progressTrackLayer(
        railWidth: CGFloat,
        playedWidth: CGFloat,
        scale: CGFloat,
        playedColor: Color
    ) -> some View {
        let visualHeight = DesignTokens.ProgressBar.trackHeight * scale
        let trackShape = RoundedRectangle(
            cornerSize: CGSize(
                width: visualHeight / 2,
                height: DesignTokens.ProgressBar.trackHeight / 2
            ),
            style: .continuous
        )

        return ZStack(alignment: .leading) {
            Color.clear
                .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
                .enchronListGroupSurface(in: trackShape, material: .thick)
            trackShape
                .fill(playedColor)
                .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: playedWidth, height: DesignTokens.ProgressBar.trackHeight)
                }
        }
        .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
    }

    private var timeBubble: some View {
        let bubbleShape = RoundedRectangle(
            cornerRadius: DesignTokens.ProgressBar.timeBubbleRadius,
            style: .continuous
        )

        return HStack(spacing: DesignTokens.Spacing.xs) {
            Text(displayedElapsedLabel).foregroundStyle(.primary)
            Text(live?.durationLabel ?? "14:15").foregroundStyle(.secondary)
        }
        .font(DesignTokens.Typography.monospacedDetail)
        .monospacedDigit()
        .padding(.horizontal, DesignTokens.ProgressBar.timeBubblePaddingH)
        .padding(.vertical, DesignTokens.ProgressBar.timeBubblePaddingV)
        .background(.thickMaterial, in: bubbleShape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("PlayerPanel-progress-time-bubble")
    }

    private func scrubberControl(width: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .overlay {
                Circle().strokeBorder(
                    DesignTokens.ProgressBar.thumbStroke,
                    lineWidth: DesignTokens.ProgressBar.thumbStrokeWidth
                )
            }
            .frame(width: DesignTokens.ProgressBar.thumbDiameter,
                   height: DesignTokens.ProgressBar.thumbDiameter)
            .accessibilityIdentifier("PlayerPanel-thumb")
            .accessibilityLabel("Playback position thumb")
            .enchronHoverContentShape(Circle())
            .enchronHoverEffect()
            .frame(width: DesignTokens.ProgressBar.thumbGrabWidth,
                   height: DesignTokens.ProgressBar.hitHeight)
            .enchronHoverContentShape(Capsule())
            .enchronHoverActivation(in: hoverActivationGroup)
            .contentShape(Capsule())
            .onHover { isProgressHovered = $0 }
    }

    private func dragGesture(width: CGFloat, thumbX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch scrubberActivation {
                case .idle:
                    guard isThumbHit(value.startLocation, thumbX: thumbX) else { return }
                    beginScrubbing(at: value.location)
                case .seeking:
                    guard let seekOrigin else { return }
                    updateProgress(
                        forTranslation: value.location.x - seekOrigin.x,
                        width: width
                    )
                }
            }
            .onEnded { value in
                guard case .seeking = scrubberActivation else {
                    resetScrubberActivation()
                    return
                }
                guard hypot(value.translation.width, value.translation.height)
                        > DesignTokens.ProgressBar.tapDragThreshold else {
                    resetScrubberActivation()
                    return
                }
                let target = PlaybackSeekPresentation.clampedTarget(progress)
                armPendingSeek(for: target)
                scrubReleaseTrigger += 1
                endScrubbing()
                live?.onSeek(target)
            }
    }

    private func seekToTrack(at locationX: CGFloat, travelWidth: CGFloat) {
        let target = PlaybackSeekPresentation.target(
            at: locationX,
            travelWidth: travelWidth,
            thumbDiameter: DesignTokens.ProgressBar.thumbDiameter
        )
        progress = target
        armPendingSeek(for: target)
        live?.onSeek(target)
        live?.onReachabilityAction("progress.seekToTrack")
        onInteraction()
    }

    private func beginScrubbing(at location: CGPoint) {
        seekOrigin = location
        dragStartProgress = displayProgress
        scrubBoundary = EnchronScrubBoundary.from(normalized: Double(displayProgress))
        scrubberActivation = .seeking
        isDragging = true
    }

    private func armPendingSeek(for target: CGFloat) {
        guard let pendingTarget = PlaybackSeekPresentation.pendingTarget(
            for: target,
            livePositionAvailable: live != nil
        ) else {
            return
        }
        pendingSeekTarget = pendingTarget
    }

    private func endScrubbing() {
        resetScrubberActivation()
    }

    private func resetScrubberActivation() {
        seekOrigin = nil
        withAnimation(DesignTokens.AnimationToken.selection) {
            scrubberActivation = .idle
            isDragging = false
        }
    }

    private func progressValue(forTranslation translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return progress }
        return min(max(dragStartProgress + translationX / width, 0), 1)
    }

    private func updateProgress(forTranslation translationX: CGFloat, width: CGFloat) {
        let nextProgress = progressValue(forTranslation: translationX, width: width)
        scrubBoundary = EnchronScrubBoundary.from(normalized: Double(nextProgress))
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { progress = nextProgress }
    }

    private func adjustProgressForAccessibility(_ direction: AccessibilityAdjustmentDirection) {
        let step = CGFloat(15 / max(timelineDuration, 15))
        let target: CGFloat
        switch direction {
        case .increment:
            target = PlaybackSeekPresentation.clampedTarget(displayProgress + step)
        case .decrement:
            target = PlaybackSeekPresentation.clampedTarget(displayProgress - step)
        @unknown default:
            return
        }
        progress = target
        armPendingSeek(for: target)
        live?.onSeek(target)
        live?.onReachabilityAction("progress.adjust")
        onInteraction()
    }

    private func openTimeline() {
        videoFormatEditing.discard()
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isDragging = false
        }
        timelineFeedbackTrigger += 1
        changeExpansion(to: .timeline)
        live?.onReachabilityAction("precisionTimeline.open")
        onInteraction()
    }

    private func closeTimeline() {
        changeExpansion(to: .collapsed)
        onInteraction()
    }

    private func toggleSettings() {
        guard let presentation = live?.presentation,
              PlaybackPanelSettingsPolicy.settingsAreAvailable(
                  for: presentation
              ) else {
            return
        }
        if expansion.isShowing(.settings) {
            videoFormatEditing.discard()
            changeExpansion(to: .collapsed)
            live?.onReachabilityAction("settings.close")
        } else {
            if PlaybackPanelSettingsPolicy.showsVideoFormatEditor(
                for: presentation
            ),
               let committedVideoFormatSelection {
                videoFormatEditing.synchronizeCommittedVideoFormat(
                    committedVideoFormatSelection
                )
                videoFormatEditing.beginEditing()
            }
            changeExpansion(to: .settings)
            live?.onReachabilityAction("settings.open")
        }
        onInteraction()
    }

    private func isThumbHit(_ location: CGPoint, thumbX: CGFloat) -> Bool {
        abs(location.x - thumbX) <= DesignTokens.ProgressBar.thumbGrabWidth / 2
    }
}

private struct DockedPlacementSliderRow: View {
    let title: String
    let liveValue: Double
    let range: ClosedRange<Double>
    let step: Double
    let trackWidth: CGFloat
    let valueLabel: (Double) -> String
    let identifier: String
    let onChange: (Double) -> Void

    @State private var draftValue: Double?
    @State private var isDragging = false

    private var displayedValue: Double {
        draftValue ?? liveValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .frame(width: 100, alignment: .leading)
                .padding(.top, 6)

            DetentedRangeSlider(
                value: Binding(
                    get: { displayedValue },
                    set: { newValue in
                        draftValue = newValue
                        onChange(newValue)
                    }
                ),
                range: range,
                step: step,
                accessibilityLabel: title,
                accessibilityValue: valueLabel(displayedValue),
                accessibilityIdentifier: "PlayerPanel-\(identifier)-slider",
                trackWidth: trackWidth,
                onDraggingChanged: { dragging in
                    isDragging = dragging
                    if !dragging {
                        draftValue = nil
                    }
                }
            )

            Text(valueLabel(displayedValue))
                .font(DesignTokens.Typography.metadata.monospacedDigit())
                .frame(minWidth: 64, alignment: .trailing)
                .padding(.top, 6)
        }
        .onChange(of: liveValue) { _, newValue in
            if !isDragging {
                draftValue = nil
            } else if draftValue == nil {
                draftValue = newValue
            }
        }
    }

}

private struct PlaybackMediaMetadataRow: View {
    let spatialMetadataLabel: String
    let technicalMetadataLabel: String

    var body: some View {
        HStack(spacing: 0) {
            Text(spatialMetadataLabel)
            Spacer(minLength: DesignTokens.Spacing.xl)
            Text(technicalMetadataLabel)
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
        }
        .font(DesignTokens.Typography.metadata.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, DesignTokens.Spacing.xl)
    }
}

#Preview("Player metadata lengths") {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
        Text("Short")
        PlaybackMediaMetadataRow(
            spatialMetadataLabel: "Flat · Mono",
            technicalMetadataLabel: "1920×1080 · SDR · H.264"
        )
        .frame(width: 440, height: DesignTokens.Layout.playbackMediaInfoHeight)
        .background(
            .thickMaterial,
            in: RoundedRectangle(
                cornerRadius: DesignTokens.Radius.element,
                style: .continuous
            )
        )

        Text("Dolby Vision Profile 5")
        PlaybackMediaMetadataRow(
            spatialMetadataLabel: "Flat · Mono",
            technicalMetadataLabel: "3840×2160 · Dolby Vision Profile 5 · HEVC · 24 fps"
        )
        .frame(width: 440, height: DesignTokens.Layout.playbackMediaInfoHeight)
        .background(
            .thickMaterial,
            in: RoundedRectangle(
                cornerRadius: DesignTokens.Radius.element,
                style: .continuous
            )
        )

        Text("Synthetic overflow")
        PlaybackMediaMetadataRow(
            spatialMetadataLabel: "Flat · Mono",
            technicalMetadataLabel: "1234567890×1234567890 · Dolby Vision Profile 2147483647.2147483647 Fallback to HDR10 · EXPERIMENTAL-EXTENDED-CODEC-IDENTIFIER · 119.88 fps"
        )
        .frame(width: 440, height: DesignTokens.Layout.playbackMediaInfoHeight)
        .background(
            .thickMaterial,
            in: RoundedRectangle(
                cornerRadius: DesignTokens.Radius.element,
                style: .continuous
            )
        )
    }
    .padding(DesignTokens.Spacing.xxl)
}
