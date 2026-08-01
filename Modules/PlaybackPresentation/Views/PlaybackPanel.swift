import DesignSystem
import Foundation
import PlaybackFeature
import PlaybackPresentation
import SwiftUI


// MARK: - Fused player panel

/// Playback and presentation bindings. A nil value lets DesignPreview render
/// the panel without constructing a playback session.
struct FusedPlayerPanelLive {
    var presentation: PlaybackPresentation
    var mediaName: String
    var mediaProfile: PlaybackModel.MediaProfile?
    var canDock: Bool
    var canEnterPanorama: Bool
    var screenScale: Double
    var recommendedScreenScale: Double
    var screenDistance: Double
    var screenElevationDegrees: Double
    var projection: PlaybackModel.ProjectionType
    var stereoLayout: PlaybackModel.StereoLayout
    var canUseFisheye: Bool
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
    var onEnterPanorama: () -> Void
    var onEnterImmersive: () -> Void
    var onExitSpatial: () -> Void
    var onExitPlayback: () -> Void
    var onSetScreenScale: @MainActor @Sendable (Double) -> Void
    var onSetScreenDistance: @MainActor @Sendable (Double) -> Void
    var onSetScreenElevation: @MainActor @Sendable (Double) -> Void
    var onResetDockedPlacement: () -> Void
    var onApplyFormat: (PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void
    var onResetFormat: () -> Void
    var subtitleItems: [DeckMenuItem]
    var audioItems: [DeckMenuItem]
    var speedItems: [DeckMenuItem]
    var episodeItems: [DeckMenuItem]
}

/// Presentation-only rules for holding a scrubber at its requested position
/// while the runtime's asynchronous seek result catches up.
enum PlaybackSeekPresentation {
    static let targetMatchTolerance: CGFloat = 0.02
    /// Position updates are the normal settlement path. This timeout only
    /// prevents a failed or unavailable position projection from holding the
    /// thumb forever.
    static let pendingTargetFallbackDuration: Duration = .milliseconds(600)

    static func clampedTarget(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
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

fileprivate enum PlaybackControlPanelSurface {
    case windowOrnament
    case playerControlDock
}

enum PlaybackPanelInitialExpansion {
    case collapsed
    case timeline
    case settings
}

struct WindowPlaybackControls: View {
    let live: FusedPlayerPanelLive
    var onInteraction: () -> Void = {}
    var initialExpansion: PlaybackPanelInitialExpansion = .collapsed

    var body: some View {
        FusedPlayerPanel(
            live: live,
            onInteraction: onInteraction,
            surface: .windowOrnament,
            initialExpansion: initialExpansion
        )
    }
}

struct PlayerControlDock: View {
    let live: FusedPlayerPanelLive
    var onInteraction: () -> Void = {}
    var initialExpansion: PlaybackPanelInitialExpansion = .collapsed

    var body: some View {
        FusedPlayerPanel(
            live: live,
            onInteraction: onInteraction,
            surface: .playerControlDock,
            initialExpansion: initialExpansion
        )
    }
}

struct FusedPlayerPanel: View {
    var live: FusedPlayerPanelLive?
    var onInteraction: () -> Void = {}
    private let surface: PlaybackControlPanelSurface

    init(
        live: FusedPlayerPanelLive? = nil,
        onInteraction: @escaping () -> Void = {},
        initialExpansion: PlaybackPanelInitialExpansion = .collapsed
    ) {
        self.live = live
        self.onInteraction = onInteraction
        self.surface = (
            (live?.presentation ?? .window) == .window
                ? .windowOrnament
                : .playerControlDock
        )
        _timelineExpanded = State(initialValue: initialExpansion == .timeline)
        _settingsExpanded = State(initialValue: initialExpansion == .settings)
    }

    fileprivate init(
        live: FusedPlayerPanelLive,
        onInteraction: @escaping () -> Void,
        surface: PlaybackControlPanelSurface,
        initialExpansion: PlaybackPanelInitialExpansion
    ) {
        self.live = live
        self.onInteraction = onInteraction
        self.surface = surface
        _timelineExpanded = State(initialValue: initialExpansion == .timeline)
        _settingsExpanded = State(initialValue: initialExpansion == .settings)
    }

    @State private var timelineExpanded: Bool
    @State private var settingsExpanded: Bool
    @State private var mediaInfoHovered = false

    // 进度条状态。拖动中用本地 progress(跟手);非拖动镜像 live 位置;live 为 nil 退化纯本地 mock。
    @State private var progress: CGFloat = 0.45
    @State private var isDragging = false
    @State private var isTimelineDragging = false
    @State private var isProgressHovered = false
    @State private var scrubberActivation: ScrubberActivation = .idle
    @State private var activationOrigin: CGPoint?
    @State private var activationCurrentLocation: CGPoint?
    @State private var seekOrigin: CGPoint?
    @State private var activationGeneration = 0
    @State private var lastScrubberPress: (time: Date, location: CGPoint)?
    @State private var dragStartProgress: CGFloat = 0.45
    /// Seek 完成锁存:松手 onSeek 后,live.progress 异步才追上,锁存期内拇指钉在目标值,
    /// 避免"跳回旧位再闪到目标"。live 追上(或超时兜底)即释放。
    @State private var pendingSeekTarget: CGFloat?
    @State private var pendingSeekGeneration = 0
    @State private var scrubFeedbackTrigger = 0
    @State private var minimumBoundaryFeedbackTrigger = 0
    @State private var maximumBoundaryFeedbackTrigger = 0
    @State private var timelineFeedbackTrigger = 0
    @State private var rewindIconAnimationTrigger = 0
    @State private var forwardIconAnimationTrigger = 0
    @State private var announcedBoundary: ProgressBoundary?
    @State private var pixelsPerSecond: CGFloat = DesignTokens.PrecisionTimeline.initialPixelsPerSecond
    // ⋯ 菜单 Canvas mock 选择态(live 为 nil 时)。
    @State private var selectedSpeed = "1×"
    @State private var advancedProjection: PlaybackModel.ProjectionType = .flat
    @State private var advancedStereoLayout: PlaybackModel.StereoLayout = .mono
    @Namespace private var hoverNamespace

    private enum ProgressBoundary { case minimum, maximum }
    private enum ScrubberActivation {
        case idle
        case activating
        case unlocked
        case seeking
        case cancelled
    }

    // 拖动中用本地 progress(视觉跟手);松手回调 onSeek。非拖动时镜像 live 位置;
    // 锁存期内钉在 pendingSeekTarget;live 为 nil 退化纯本地 @State(Canvas mock)。
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

    private var isExpanded: Bool { timelineExpanded || settingsExpanded }
    private var clusterWidth: CGFloat {
        isExpanded
            ? DesignTokens.Layout.expandedPlayerControlsContentWidth
            : DesignTokens.ControlBar.contentWidth
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
    }

    var body: some View {
        Group {
            switch surface {
            case .windowOrnament:
                windowOrnamentContent
            case .playerControlDock:
                playerControlDockContent
            }
        }
        .frame(width: clusterWidth)
        .padding(.horizontal, DesignTokens.ControlBar.paddingH)
        .padding(.vertical, DesignTokens.ControlBar.paddingV)
        .clipShape(shape)
        .enchronGlassBackground(in: shape)
        // 旋转(向用户抬起 30°)留到真实窗口/ornament 语境再加——Canvas 预览不出空间旋转。
        .animation(DesignTokens.AnimationToken.panelSpring, value: timelineExpanded)
        .animation(DesignTokens.AnimationToken.panelSpring, value: settingsExpanded)
        .enchronPressSensoryFeedback(.slider, trigger: scrubFeedbackTrigger)
        .enchronPressSensoryFeedback(.selectionMinimum, trigger: minimumBoundaryFeedbackTrigger)
        .enchronPressSensoryFeedback(.selectionMaximum, trigger: maximumBoundaryFeedbackTrigger)
        .enchronPressSensoryFeedback(.selectionOn, trigger: timelineFeedbackTrigger)
        .onChange(of: live?.progress) { _, newValue in
            // 锁存释放:player 报告的位置追上(容差内)目标即放行。
            guard let target = pendingSeekTarget, let newValue else { return }
            if PlaybackSeekPresentation.target(target, matches: newValue) {
                pendingSeekTarget = nil
            }
        }
        .task(id: pendingSeekGeneration) {
            // 兜底:player 永远不精确落到目标时,别让锁存无限钉住拇指。
            guard let target = pendingSeekTarget else { return }
            let generation = pendingSeekGeneration
            try? await Task.sleep(
                for: PlaybackSeekPresentation.pendingTargetFallbackDuration
            )
            guard !Task.isCancelled,
                  pendingSeekGeneration == generation,
                  pendingSeekTarget == target else { return }
            pendingSeekTarget = nil
        }
    }

    @ViewBuilder
    private var windowOrnamentContent: some View {
        if timelineExpanded {
            VStack(spacing: DesignTokens.Spacing.md) {
                windowTransportControls
                timelineBlock
            }
        } else {
            HStack(spacing: DesignTokens.Spacing.md) {
                windowTransportControls
                progressBar(width: windowProgressWidth)
            }
        }
    }

    private var playerControlDockContent: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            mediaInformationWell
            playerControlDockControls

            if settingsExpanded, let live, live.presentation == .docked {
                dockedPlacementControls(live)
            }

            if settingsExpanded, let live, live.presentation == .panorama {
                panoramaFormatControls(live)
            }

            if timelineExpanded {
                timelineBlock
            } else {
                progressBar(width: clusterWidth)
            }
        }
    }

    private var windowProgressWidth: CGFloat {
        clusterWidth
            - DesignTokens.Interactive.large * 3
            - DesignTokens.ControlBar.buttonSpacing * 2
            - DesignTokens.Spacing.md
    }

    private func panoramaFormatControls(_ live: FusedPlayerPanelLive) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Picker("Projection", selection: $advancedProjection) {
                Text("180°").tag(PlaybackModel.ProjectionType.equirectangular180)
                Text("360°").tag(PlaybackModel.ProjectionType.equirectangular360)
                if live.canUseFisheye {
                    Text("Fisheye").tag(PlaybackModel.ProjectionType.fisheye)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("PlayerPanel-Advanced-Projection")

            Picker("Stereo Layout", selection: $advancedStereoLayout) {
                Text("Mono").tag(PlaybackModel.StereoLayout.mono)
                Text("Side-by-Side").tag(PlaybackModel.StereoLayout.sideBySide)
                Text("Top-Bottom").tag(PlaybackModel.StereoLayout.topBottom)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("PlayerPanel-Advanced-StereoLayout")

            HStack {
                Button("Reset to Flat + Mono") { live.onResetFormat() }
                    .accessibilityIdentifier("PlayerPanel-Advanced-ResetFormat")
                Spacer()
                Button("Apply") {
                    live.onApplyFormat(advancedProjection, advancedStereoLayout)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("PlayerPanel-Advanced-ApplyFormat")
            }
        }
    }

    private func dockedPlacementControls(_ live: FusedPlayerPanelLive) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            placementSlider(
                title: "Screen Size",
                value: live.screenScale,
                range: PlaybackScreenSize.scaleRange,
                step: PlaybackScreenSize.scaleStep,
                valueLabel: "\(Int((live.screenScale * 100).rounded()))%",
                identifier: "ScreenSize",
                onChange: live.onSetScreenScale
            )
            placementSlider(
                title: "Distance",
                value: live.screenDistance,
                range: PlaybackDockedPlacement.distanceRange,
                step: PlaybackDockedPlacement.distanceStep,
                valueLabel: String(format: "%.1f m", live.screenDistance),
                identifier: "Distance",
                onChange: live.onSetScreenDistance
            )
            placementSlider(
                title: "Elevation",
                value: live.screenElevationDegrees,
                range: PlaybackDockedPlacement.elevationRange,
                step: PlaybackDockedPlacement.elevationStep,
                valueLabel: "\(Int(live.screenElevationDegrees.rounded()))°",
                identifier: "Elevation",
                onChange: live.onSetScreenElevation
            )
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    onInteraction()
                    live.onResetDockedPlacement()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("PlayerPanel-DockedPlacement-reset")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-DockedPlacement")
    }

    private func placementSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueLabel: String,
        identifier: String,
        onChange: @escaping @MainActor @Sendable (Double) -> Void
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .frame(width: 100, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: onChange),
                in: range,
                step: step,
                onEditingChanged: { _ in onInteraction() }
            )
            .accessibilityIdentifier("PlayerPanel-\(identifier)-slider")
            .accessibilityLabel(title)
            .accessibilityValue(valueLabel)
            Text(valueLabel)
                .font(DesignTokens.Typography.metadata.monospacedDigit())
                .frame(minWidth: 64, alignment: .trailing)
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
                        GlassCircleIconButton.settings(
                            accessibilityLabel: settingsExpanded ? "Close Advanced Settings" : "Open Advanced Settings",
                            action: toggleSettings,
                            accessibilityIdentifier: "PlayerPanel-button-settings"
                        )
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
            .frame(width: clusterWidth, height: DesignTokens.Interactive.xl)
        }
    }

    private var mediaInformationWell: some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.element,
            style: .continuous
        )
        return ZStack {
            Text(live?.mediaName ?? "Unknown")
                .font(DesignTokens.Typography.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .enchronHoverOpacity(
                    active: 0,
                    inactive: 1,
                    in: mediaInfoHoverRevealGroup,
                    forcedActive: mediaInfoHovered,
                    animation: DesignTokens.AnimationToken.selection
                )

            Text(live?.mediaName ?? "Unknown")
                .font(DesignTokens.Typography.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .offset(y: -DesignTokens.Spacing.sm)
                .enchronHoverOpacity(
                    active: 1,
                    inactive: 0,
                    in: mediaInfoHoverRevealGroup,
                    forcedActive: mediaInfoHovered,
                    animation: DesignTokens.AnimationToken.selection
                )

            HStack(spacing: DesignTokens.Spacing.xl) {
                Text(spatialMetadataLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(technicalMetadataLabel)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(DesignTokens.Typography.metadata.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, DesignTokens.Spacing.sm)
            .enchronHoverOpacity(
                active: 1,
                inactive: 0,
                in: mediaInfoHoverRevealGroup,
                forcedActive: mediaInfoHovered,
                animation: DesignTokens.AnimationToken.selection
            )
        }
        .frame(width: clusterWidth, height: DesignTokens.Layout.playbackMediaInfoHeight)
        .background(.thickMaterial, in: shape)
        .overlay {
            shape.stroke(.white.opacity(0.08), lineWidth: DesignTokens.Stroke.subtle)
        }
        .contentShape(.interaction, shape)
        .enchronHoverContentShape(shape)
        .enchronHoverActivation(in: mediaInfoHoverActivationGroup)
        .onHover { hovering in
            withAnimation(DesignTokens.AnimationToken.panelSpring) {
                mediaInfoHovered = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(live?.mediaName ?? "Unknown media")
        .accessibilityValue("\(spatialMetadataLabel), \(technicalMetadataLabel)")
        .accessibilityIdentifier("PlayerPanel-media-information")
    }

    private var mediaInfoHoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "media-information", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var mediaInfoHoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "media-information", in: hoverNamespace, behavior: .followsGroup)
    }

    private var spatialMetadataLabel: String {
        guard let live else { return "Flat · Mono" }
        return "\(projectionLabel(live.projection)) · \(stereoLabel(live.stereoLayout))"
    }

    private var technicalMetadataLabel: String {
        guard let profile = live?.mediaProfile else { return "Media information unavailable" }
        var parts = ["\(profile.resolution.width)×\(profile.resolution.height)"]
        parts.append(PlaybackInfoFormatter.hdrTypeLabel(profile.hdrType))
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
        case .fisheye: "Fisheye"
        }
    }

    private func stereoLabel(_ stereo: PlaybackModel.StereoLayout) -> String {
        switch stereo {
        case .mono: "Mono"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }

    @ViewBuilder
    private func returnToWindowButton(_ live: FusedPlayerPanelLive) -> some View {
        if live.presentation == .panorama {
            GlassCircleIconButton.collapseVertically(
                accessibilityLabel: "Return to Window",
                action: live.onExitSpatial,
                accessibilityIdentifier: "PlayerPanel-button-exit-spatial"
            )
            .keyboardShortcut(.escape, modifiers: [])
        } else {
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
            accessibilityLabel: timelineExpanded ? "Previous frame" : "Rewind 15 seconds",
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
            accessibilityLabel: timelineExpanded ? "Next frame" : "Forward 15 seconds",
            action: performForwardAction,
            animationTrigger: forwardIconAnimationTrigger,
            visualSize: DesignTokens.Interactive.regular,
            targetSize: DesignTokens.Interactive.large,
            iconTier: .standard
        )
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(
            timelineExpanded
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
            accessibilityLabel: timelineExpanded ? "Previous frame" : "Rewind 15 seconds",
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
            accessibilityLabel: timelineExpanded ? "Next frame" : "Forward 15 seconds",
            action: performForwardAction,
            animationTrigger: forwardIconAnimationTrigger
        )
        .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(
                timelineExpanded
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
        if timelineExpanded {
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
        if timelineExpanded {
            stepFrame(-1)
        } else {
            rewindIconAnimationTrigger &+= 1
            live?.onSkipBackward()
        }
    }

    private func performForwardAction() {
        if timelineExpanded {
            stepFrame(1)
        } else {
            forwardIconAnimationTrigger &+= 1
            live?.onSkipForward()
        }
    }

    // ⋯ 菜单:玻璃圆(GlassCircleIconLabel)作 Menu label,内容 live 注入时来自产品层、
    // 否则 Canvas mock。命中尺寸对齐其它 transport 玻璃圆(large 60)。
    private var moreMenu: some View {
        Menu {
            if let live {
                liveMoreMenuSections(live)
            } else {
                mockMoreMenuSections
            }
        } label: {
            GlassCircleIconLabel(
                systemName: "ellipsis",
                accessibilityLabel: "More",
                accessibilityIdentifier: "PlayerPanel-menu-more"
            )
        }
        .buttonStyle(.plain)
        .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
        .contentShape(Circle())
        .accessibilityIdentifier("PlayerPanel-menu-more")
        .accessibilityLabel("More playback settings")
    }

    /// 逐帧步进:live 注入时回调产品层;否则在 mock 本地 progress 上挪一帧。
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
            visualSize: DesignTokens.Interactive.xl,
            targetSize: DesignTokens.Interactive.xl,
            iconTier: .primary
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
                menuOption("Episode 2 · Night Crossing")
                menuOption("Episode 3 · Glass Harbor")
                menuOption("Episode 4 · Quiet Orbit")
                menuOption("Episode 5 · Afterimage")
                menuOption("Episode 6 · The Long Return")
            }
        }
    }

    @ViewBuilder
    private func liveMoreMenuSections(_ live: FusedPlayerPanelLive) -> some View {
        Section("Playback Settings") {
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
    }

    @ViewBuilder
    private func liveMenuItems(
        _ items: [DeckMenuItem],
        category: String
    ) -> some View {
        Picker("", selection: liveSelection(items)) {
            ForEach(items) { item in
                Text(item.title)
                    .tag(item.id)
                    .accessibilityIdentifier("PlayerPanel-menu-\(category)-\(item.id)")
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func liveSelection(_ items: [DeckMenuItem]) -> Binding<String> {
        Binding(
            get: { items.first(where: \.isSelected)?.id ?? "" },
            set: { id in items.first(where: { $0.id == id })?.action() }
        )
    }

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

    // MARK: Timeline(展开态)

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
        // 对称:双击进度条展开,双击时间轴收起。
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

    // MARK: Progress bar(收起态;双击展开时间轴)—— 整套抄自 PlayerControlDeck

    private var trackScale: CGFloat {
        switch scrubberActivation {
        case .activating, .unlocked, .seeking:
            return 1
        case .idle, .cancelled:
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
        ZStack(alignment: .leading) {
            progressInteractionRegion(width: overlayWidth)

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
                    animation: DesignTokens.AnimationToken.selection,
                    macUsesLocalHover: true
                )
                .allowsHitTesting(false)

            scrubberControl(width: width)
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2
                )
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .contentShape(.interaction, Capsule())
        .gesture(dragGesture(width: width, thumbX: thumbX))
    }

    private func progressInteractionRegion(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(.interaction, Capsule())
            .onHover { isProgressHovered = $0 }
            .accessibilityElement(children: .ignore)
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
                    animation: DesignTokens.AnimationToken.selection,
                    macUsesLocalHover: true
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
        .enchronGlassBackground(in: bubbleShape)
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
            .frame(width: DesignTokens.ProgressBar.hitHeight,
                   height: DesignTokens.ProgressBar.hitHeight)
            .enchronHoverContentShape(Circle())
            .enchronHoverActivation(in: hoverActivationGroup)
            .contentShape(Circle())
            .onHover { isProgressHovered = $0 }
    }

    private func dragGesture(width: CGFloat, thumbX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch scrubberActivation {
                case .idle:
                    guard isThumbHit(value.startLocation, thumbX: thumbX) else {
                        lastScrubberPress = nil
                        scrubberActivation = .cancelled
                        return
                    }
                    beginScrubberActivation(at: value.location)
                case .activating:
                    guard let origin = activationOrigin else { return }
                    if distance(from: origin, to: value.location) > DesignTokens.ProgressBar.activationSlop {
                        cancelScrubberActivation()
                    } else {
                        activationCurrentLocation = value.location
                    }
                case .unlocked:
                    beginScrubbing(at: value.location)
                case .seeking:
                    guard let seekOrigin else { return }
                    updateProgress(
                        forTranslation: value.location.x - seekOrigin.x,
                        width: width
                    )
                case .cancelled:
                    return
                }
            }
            .onEnded { value in
                if scrubberActivation == .seeking {
                    lastScrubberPress = nil
                    let target = PlaybackSeekPresentation.clampedTarget(progress)
                    // 先锁存目标,再释放 dragging;否则 SwiftUI 可能先镜像
                    // 旧 live.position 一帧,使拇指出现回跳。
                    armPendingSeek(for: target)
                    endScrubbing()
                    live?.onSeek(target)
                } else if scrubberActivation == .activating {
                    completeShortScrubberPress(at: value.location, time: value.time)
                    resetScrubberActivation()
                } else {
                    resetScrubberActivation()
                }
            }
    }

    private func completeShortScrubberPress(at location: CGPoint, time: Date) {
        if let previous = lastScrubberPress,
           time.timeIntervalSince(previous.time) <= DesignTokens.ProgressBar.doublePressInterval,
           distance(from: previous.location, to: location) <= DesignTokens.ProgressBar.activationSlop {
            lastScrubberPress = nil
            openTimeline()
        } else {
            lastScrubberPress = (time, location)
        }
    }

    private func beginScrubberActivation(at location: CGPoint) {
        activationGeneration += 1
        let generation = activationGeneration
        activationOrigin = location
        activationCurrentLocation = location
        seekOrigin = nil
        dragStartProgress = displayProgress
        progress = displayProgress
        withAnimation(DesignTokens.ProgressBar.activationAnimation) {
            scrubberActivation = .activating
        }
        Task { @MainActor in
            try? await Task.sleep(for: DesignTokens.ProgressBar.activationDuration)
            guard Task.isCancelled == false else { return }
            guard activationGeneration == generation else { return }
            guard scrubberActivation == .activating else { return }
            lastScrubberPress = nil
            seekOrigin = activationCurrentLocation
            scrubberActivation = .unlocked
            scrubFeedbackTrigger += 1
        }
    }

    private func cancelScrubberActivation() {
        activationGeneration += 1
        lastScrubberPress = nil
        activationOrigin = nil
        activationCurrentLocation = nil
        seekOrigin = nil
        withAnimation(DesignTokens.AnimationToken.selection) {
            scrubberActivation = .cancelled
            isDragging = false
        }
    }

    private func beginScrubbing(at location: CGPoint) {
        seekOrigin = location
        dragStartProgress = displayProgress
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
        pendingSeekGeneration += 1
    }

    private func endScrubbing() {
        resetScrubberActivation()
        announcedBoundary = nil
    }

    private func resetScrubberActivation() {
        activationGeneration += 1
        activationOrigin = nil
        activationCurrentLocation = nil
        seekOrigin = nil
        withAnimation(DesignTokens.AnimationToken.selection) {
            scrubberActivation = .idle
            isDragging = false
        }
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func progressValue(forTranslation translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return progress }
        return min(max(dragStartProgress + translationX / width, 0), 1)
    }

    private func updateProgress(forTranslation translationX: CGFloat, width: CGFloat) {
        let nextProgress = progressValue(forTranslation: translationX, width: width)
        updateBoundaryFeedback(for: nextProgress)
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
        onInteraction()
    }

    private func updateBoundaryFeedback(for nextProgress: CGFloat) {
        let boundary: ProgressBoundary?
        if nextProgress <= 0 {
            boundary = .minimum
        } else if nextProgress >= 1 {
            boundary = .maximum
        } else {
            boundary = nil
        }
        guard boundary != announcedBoundary else { return }
        announcedBoundary = boundary
        switch boundary {
        case .minimum: minimumBoundaryFeedbackTrigger += 1
        case .maximum: maximumBoundaryFeedbackTrigger += 1
        case nil: break
        }
    }

    private func openTimeline() {
        settingsExpanded = false
        if let live {
            advancedProjection = live.projection
            advancedStereoLayout = live.stereoLayout
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isDragging = false
            announcedBoundary = nil
        }
        timelineFeedbackTrigger += 1
        withAnimation(DesignTokens.AnimationToken.panelSpring) { timelineExpanded = true }
        onInteraction()
    }

    private func closeTimeline() {
        withAnimation(DesignTokens.AnimationToken.panelSpring) { timelineExpanded = false }
        onInteraction()
    }

    private func toggleSettings() {
        if settingsExpanded {
            withAnimation(DesignTokens.AnimationToken.panelSpring) {
                settingsExpanded = false
            }
        } else {
            timelineExpanded = false
            withAnimation(DesignTokens.AnimationToken.panelSpring) {
                settingsExpanded = true
            }
        }
        onInteraction()
    }

    private func isThumbHit(_ location: CGPoint, thumbX: CGFloat) -> Bool {
        let thumbCenter = CGPoint(x: thumbX, y: DesignTokens.ProgressBar.hitHeight / 2)
        let hitRadius = DesignTokens.ProgressBar.hitHeight / 2
        let dx = location.x - thumbCenter.x
        let dy = location.y - thumbCenter.y
        return (dx * dx + dy * dy) <= (hitRadius * hitRadius)
    }
}
