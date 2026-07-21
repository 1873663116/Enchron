import SwiftUI


// MARK: - Fused player panel

/// Playback and presentation bindings. A nil value lets DesignPreview render
/// the panel without constructing a playback session.
struct FusedPlayerPanelLive {
    var presentation: PlaybackPresentation
    var canDock: Bool
    var canEnterPanorama: Bool
    var screenScale: Double
    var recommendedScreenScale: Double
    var isPlaying: Bool
    var showsReplay: Bool
    var progress: CGFloat
    var elapsedLabel: String
    var remainingLabel: String
    var duration: Double
    var framesPerSecond: Double
    var onPlayPause: () -> Void
    var onSkipBackward: () -> Void
    var onSkipForward: () -> Void
    var onSeek: (CGFloat) -> Void
    var onFrameStep: (Int) -> Void
    var onEnterPanorama: () -> Void
    var onEnterImmersive: () -> Void
    var onExitSpatial: () -> Void
    var onSetScreenScale: (Double) -> Void
    var onResetScreenScale: () -> Void
    var subtitleItems: [DeckMenuItem]
    var audioItems: [DeckMenuItem]
    var speedItems: [DeckMenuItem]
    var episodeItems: [DeckMenuItem]
}

struct FusedPlayerPanel: View {
    var live: FusedPlayerPanelLive?
    var onInteraction: () -> Void = {}

    init(
        live: FusedPlayerPanelLive? = nil,
        onInteraction: @escaping () -> Void = {},
        initialTimelineExpanded: Bool = false
    ) {
        self.live = live
        self.onInteraction = onInteraction
        _timelineExpanded = State(initialValue: initialTimelineExpanded)
    }

    @State private var timelineExpanded = false

    // 进度条状态。拖动中用本地 progress(跟手);非拖动镜像 live 位置;live 为 nil 退化纯本地 mock。
    @State private var progress: CGFloat = 0.45
    @State private var isDragging = false
    @State private var isTimelineDragging = false
    @State private var isProgressHovered = false
    @State private var isIgnoringDrag = false
    @State private var dragStartProgress: CGFloat = 0.45
    /// Seek 完成锁存:松手 onSeek 后,live.progress 异步才追上,锁存期内拇指钉在目标值,
    /// 避免"跳回旧位再闪到目标"。live 追上(或超时兜底)即释放。
    @State private var pendingSeekTarget: CGFloat?
    @State private var scrubFeedbackTrigger = 0
    @State private var minimumBoundaryFeedbackTrigger = 0
    @State private var maximumBoundaryFeedbackTrigger = 0
    @State private var timelineFeedbackTrigger = 0
    @State private var announcedBoundary: ProgressBoundary?
    @State private var pixelsPerSecond: CGFloat = DesignTokens.PrecisionTimeline.initialPixelsPerSecond
    // ⋯ 菜单 Canvas mock 选择态(live 为 nil 时)。
    @State private var selectedSubtitle = "Off"
    @State private var selectedAudioTrack = "English 5.1"
    @State private var selectedSpeed = "1×"
    @Namespace private var hoverNamespace

    private enum ProgressBoundary { case minimum, maximum }

    // 拖动中用本地 progress(视觉跟手);松手回调 onSeek。非拖动时镜像 live 位置;
    // 锁存期内钉在 pendingSeekTarget;live 为 nil 退化纯本地 @State(Canvas mock)。
    private var displayProgress: CGFloat {
        if isDragging || isTimelineDragging { return progress }
        if let pendingSeekTarget { return pendingSeekTarget }
        return live?.progress ?? progress
    }

    private let expandedWidth: CGFloat = 880

    private var isExpanded: Bool { timelineExpanded }
    private var clusterWidth: CGFloat {
        isExpanded ? expandedWidth : DesignTokens.ProgressBar.previewWidth
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            controlsRow

            if let live, live.presentation == .docked {
                screenSizeControl(live)
            }

            // 控件簇第二行(与按钮同属"播放控制",无分界线):时间轴收起时是进度条
            // ——进度条本身就是打开时间轴的按钮(双击展开);展开时同槽位换成时间轴本体。
            if timelineExpanded {
                timelineBlock
            } else {
                progressBar
            }

        }
        .padding(DesignTokens.Spacing.xl)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        // 旋转(向用户抬起 30°)留到真实窗口/ornament 语境再加——Canvas 预览不出空间旋转。
        .animation(DesignTokens.AnimationToken.panelSpring, value: timelineExpanded)
        .sensoryFeedback(.press(.slider), trigger: scrubFeedbackTrigger)
        .sensoryFeedback(.selection(.minimum), trigger: minimumBoundaryFeedbackTrigger)
        .sensoryFeedback(.selection(.maximum), trigger: maximumBoundaryFeedbackTrigger)
        .sensoryFeedback(.selection(.on), trigger: timelineFeedbackTrigger)
        .onChange(of: live?.progress) { _, newValue in
            // 锁存释放:player 报告的位置追上(容差内)目标即放行。
            guard let target = pendingSeekTarget, let newValue else { return }
            if abs(newValue - target) < 0.02 { pendingSeekTarget = nil }
        }
        .task(id: pendingSeekTarget) {
            // 兜底:player 永远不精确落到目标时,别让锁存无限钉住拇指。
            guard pendingSeekTarget != nil else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            pendingSeekTarget = nil
        }
    }

    private func screenSizeControl(_ live: FusedPlayerPanelLive) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("Screen Size")
                .font(DesignTokens.Typography.metadata)

            Slider(
                value: Binding(
                    get: { live.screenScale },
                    set: { live.onSetScreenScale($0) }
                ),
                in: PlaybackScreenSize.scaleRange,
                step: PlaybackScreenSize.scaleStep,
                onEditingChanged: { _ in onInteraction() }
            )
            .accessibilityIdentifier("PlayerPanel-ScreenSize-slider")
            .accessibilityLabel("Screen Size")
            .accessibilityValue("\(Int((live.screenScale * 100).rounded())) percent")

            Text("\(Int((live.screenScale * 100).rounded()))%")
                .font(DesignTokens.Typography.metadata.monospacedDigit())
                .frame(minWidth: 52, alignment: .trailing)
                .accessibilityIdentifier("PlayerPanel-ScreenSize-value")

            Button("Reset") {
                onInteraction()
                live.onResetScreenScale()
            }
            .buttonStyle(.borderless)
            .disabled(abs(live.screenScale - live.recommendedScreenScale) < 0.001)
            .accessibilityIdentifier("PlayerPanel-ScreenSize-reset")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-ScreenSize")
    }

    @ViewBuilder
    private var controlsRow: some View {
        if (live?.presentation ?? .window) == .window {
            HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                GlassCircleIconButton(
                    systemName: "slider.horizontal.3",
                    accessibilityLabel: timelineExpanded ? "Collapse playback panel" : "Expand playback panel",
                    action: { timelineExpanded ? closeTimeline() : openTimeline() },
                    accessibilityIdentifier: "PlayerPanel-button-expand"
                )
                GlassCircleIconButton(
                    systemName: "square.stack.3d.up",
                    accessibilityLabel: "Docking",
                    action: { live?.onEnterImmersive() },
                    accessibilityIdentifier: "PlayerPanel-button-dock"
                )
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!(live?.canDock ?? true))
                rewindButton
                playButton
                forwardButton
                #if os(visionOS)
                GlassCircleIconButton(
                    systemName: "pano",
                    accessibilityLabel: "Panorama",
                    action: { live?.onEnterPanorama() },
                    accessibilityIdentifier: "PlayerPanel-button-panorama"
                )
                .disabled(!(live?.canEnterPanorama ?? true))
                #endif
                moreMenu
            }
            .frame(width: clusterWidth)
        } else if let live {
            HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                GlassCircleIconButton(
                    systemName: live.presentation == .docked ? "rectangle.portrait.and.arrow.forward" : "pano",
                    accessibilityLabel: live.presentation == .docked ? "Undock" : "Exit Panorama",
                    action: live.onExitSpatial,
                    accessibilityIdentifier: "PlayerPanel-button-exit-spatial"
                )
                .keyboardShortcut(.escape, modifiers: [])
                rewindButton
                playButton
                forwardButton
                moreMenu
            }
            .frame(width: clusterWidth)
        }
    }

    private var rewindButton: some View {
        GlassCircleIconButton(
            systemName: timelineExpanded ? "backward.frame" : "gobackward.10",
            accessibilityLabel: timelineExpanded ? "Previous frame" : "Rewind 10 seconds",
            action: { timelineExpanded ? stepFrame(-1) : live?.onSkipBackward() },
            accessibilityIdentifier: "PlayerPanel-button-rewind"
        )
        .keyboardShortcut(.leftArrow, modifiers: [])
    }

    private var forwardButton: some View {
        GlassCircleIconButton(
            systemName: timelineExpanded ? "forward.frame" : "goforward.10",
            accessibilityLabel: timelineExpanded ? "Next frame" : "Forward 10 seconds",
            action: { timelineExpanded ? stepFrame(1) : live?.onSkipForward() },
            accessibilityIdentifier: "PlayerPanel-button-forward"
        )
        .keyboardShortcut(.rightArrow, modifiers: [])
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
            font: DesignTokens.SymbolSize.action
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

    // MARK: ⋯ 菜单内容(live 注入 / Canvas mock 两路,抄自原 PlayerControlDeck)

    @ViewBuilder
    private var mockMoreMenuSections: some View {
        Section("Playback Settings") {
            mockSelectableMenu("Subtitles", ["Off", "English CC", "中文简体", "Auto"], selection: $selectedSubtitle)
            mockSelectableMenu("Audio Track", ["English 5.1", "Japanese 2.0", "Commentary"], selection: $selectedAudioTrack)
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
            if !live.subtitleItems.isEmpty {
                Menu("Subtitles") {
                    liveMenuItems(live.subtitleItems, category: "subtitle")
                }
                .accessibilityIdentifier("PlayerPanel-menu-subtitles")
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
        .frame(width: expandedWidth, height: DesignTokens.PrecisionTimeline.expandedHeight)
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
        isTimelineDragging = false
        guard let live, timelineDuration > 0 else { return }
        let target = CGFloat(min(max(seconds / timelineDuration, 0), 1))
        progress = target
        pendingSeekTarget = target
        live.onSeek(target)
    }

    private func beginTimelineSeek() {
        progress = displayProgress
        isTimelineDragging = true
        onInteraction()
    }

    // MARK: Progress bar(收起态;双击展开时间轴)—— 整套抄自 PlayerControlDeck

    private var trackScale: CGFloat {
        isDragging ? 1 : DesignTokens.ProgressBar.inactiveScale
    }

    private var hoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "fused-progress-reveal", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var hoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "fused-progress-reveal", in: hoverNamespace, behavior: .followsGroup)
    }

    private var progressBar: some View {
        let overlayWidth = clusterWidth
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
            hoverCarrier(width: overlayWidth)

            progressHub(
                width: width,
                progress: clampedProgress,
                overlayWidth: overlayWidth,
                scale: trackScale
            )

            timeBubble
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2 - DesignTokens.ProgressBar.timeBubbleOffset
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
        .onHover { isProgressHovered = $0 }
        .gesture(dragGesture(width: width, thumbX: thumbX))
        // 双击进度条任意处展开时间轴。
        .simultaneousGesture(TapGesture(count: 2).onEnded { openTimeline() })
    }

    private func hoverCarrier(width: CGFloat) -> some View {
        Capsule()
            .fill(DesignTokens.ProgressBar.hoverCarrierFill)
            .frame(width: width, height: DesignTokens.ProgressBar.hitHeight)
            .enchronHoverContentShape(Capsule())
            .enchronHoverOpacity(
                active: 1,
                inactive: DesignTokens.ProgressBar.hoverCarrierInactiveOpacity,
                in: hoverActivationGroup,
                forcedActive: isProgressHovered,
                animation: DesignTokens.AnimationToken.selection,
                macUsesLocalHover: true
            )
            .contentShape(.interaction, Capsule())
            .accessibilityHidden(true)
    }

    private func progressHub(
        width: CGFloat,
        progress: CGFloat,
        overlayWidth: CGFloat,
        scale: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(width: overlayWidth, height: DesignTokens.ProgressBar.trackHeight)
                    .glassBackgroundEffect(in: Capsule())

                progressTrackLayer(
                    railWidth: overlayWidth,
                    playedWidth: DesignTokens.ProgressBar.thumbDiameter / 2 + width * progress,
                    scale: scale,
                    playedColor: DesignTokens.ProgressBar.playedColor,
                    unplayedColor: DesignTokens.ProgressBar.unplayedColor
                )

                progressTrackLayer(
                    railWidth: overlayWidth,
                    playedWidth: DesignTokens.ProgressBar.thumbDiameter / 2 + width * progress,
                    scale: scale,
                    playedColor: DesignTokens.ProgressBar.playedHoverColor,
                    unplayedColor: DesignTokens.ProgressBar.unplayedHoverColor
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
            .animation(DesignTokens.PressFeedback.control.pressAnimation, value: scale)
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .allowsHitTesting(false)
    }

    private func progressTrackLayer(
        railWidth: CGFloat,
        playedWidth: CGFloat,
        scale: CGFloat,
        playedColor: Color,
        unplayedColor: Color
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
            trackShape
                .fill(unplayedColor)
                .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
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
            Text(live?.elapsedLabel ?? "6:21").foregroundStyle(.primary)
            Text(live?.remainingLabel ?? "-7:54").foregroundStyle(.secondary)
        }
        .font(DesignTokens.Typography.monospacedDetail)
        .monospacedDigit()
        .padding(.horizontal, DesignTokens.ProgressBar.timeBubblePaddingH)
        .padding(.vertical, DesignTokens.ProgressBar.timeBubblePaddingV)
        .glassBackgroundEffect(in: bubbleShape)
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
    }

    private func dragGesture(width: CGFloat, thumbX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                guard !isIgnoringDrag else { return }
                if !isDragging {
                    guard isThumbHit(value.startLocation, thumbX: thumbX) else {
                        isIgnoringDrag = true
                        return
                    }
                    // live 注入时进度起点取自当前播放位置(displayProgress),避免从陈旧
                    // 本地 @State 起跳;mock 时 displayProgress == progress,行为不变。
                    dragStartProgress = displayProgress
                    progress = displayProgress
                    beginScrubbing()
                }
                updateProgress(forTranslation: value.translation.width, width: width)
            }
            .onEnded { _ in
                if isDragging {
                    endScrubbing()
                    if live != nil {
                        // 锁存到目标值,跨过异步 seek 往返;live 追上后释放(见 body 的 onChange)。
                        pendingSeekTarget = progress
                    }
                    live?.onSeek(progress)
                }
                isIgnoringDrag = false
            }
    }

    private func beginScrubbing() {
        withAnimation(DesignTokens.PressFeedback.control.pressAnimation) { isDragging = true }
        scrubFeedbackTrigger += 1
    }

    private func endScrubbing() {
        withAnimation(DesignTokens.AnimationToken.selection) { isDragging = false }
        announcedBoundary = nil
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
        onInteraction()
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isDragging = false
            announcedBoundary = nil
        }
        timelineFeedbackTrigger += 1
        withAnimation(DesignTokens.AnimationToken.panelSpring) { timelineExpanded = true }
    }

    private func closeTimeline() {
        onInteraction()
        withAnimation(DesignTokens.AnimationToken.panelSpring) { timelineExpanded = false }
    }

    private func isThumbHit(_ location: CGPoint, thumbX: CGFloat) -> Bool {
        let thumbCenter = CGPoint(x: thumbX, y: DesignTokens.ProgressBar.hitHeight / 2)
        let hitRadius = DesignTokens.ProgressBar.hitHeight / 2
        let dx = location.x - thumbCenter.x
        let dy = location.y - thumbCenter.y
        return (dx * dx + dy * dy) <= (hitRadius * hitRadius)
    }
}
