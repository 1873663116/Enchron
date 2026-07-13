import SwiftUI
import UIKit

struct WindowPlaybackPage: View {
    static let aspectRatio = CGSize(width: 16, height: 9)
    static let minimumContentSize = CGSize(width: 960, height: 540)
    static let idealContentSize = CGSize(width: 1280, height: 720)
    static let maximumContentSize = CGSize(width: 1600, height: 900)

    private static let designContentSize = idealContentSize

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isChromeVisible: Bool
    @State private var isSettingsPanelPresented: Bool
    // 蓝图状态(UC-PLAY-02 / 23):续播提示与加载失败面板。默认都不显示,运行时行为不变;
    // 仅供 Canvas 审查时通过 init 直接呈现。
    private let showsResumePrompt: Bool
    private let showsLoadFailure: Bool
    // 动画分两层:mounted = 是否在 ornament 里挂载(关闭动画放完才卸载);
    // revealed = 入场进度(同时驱动 opacity / 从上往下位移 / 合页旋转,一气呵成)。
    @State private var deckMounted: Bool
    @State private var deckRevealed: Bool
    private let initialTimelineExpanded: Bool

    // 默认隐藏 chrome(点击画面召出);initial* 参数仅供 Canvas 截图/审查时直接
    // 展示对应状态,不改变运行时的「点按显隐 / 双击展开」行为。
    init(
        initialChromeVisible: Bool = false,
        initialSettingsPanelPresented: Bool = false,
        initialTimelineExpanded: Bool = false,
        showsResumePrompt: Bool = false,
        showsLoadFailure: Bool = false
    ) {
        _isChromeVisible = State(initialValue: initialChromeVisible)
        _isSettingsPanelPresented = State(initialValue: initialSettingsPanelPresented)
        // 初始态预览直接呈现完成态(不播放入场动画)。
        let deckShown = initialChromeVisible
        _deckMounted = State(initialValue: deckShown)
        _deckRevealed = State(initialValue: deckShown)
        self.initialTimelineExpanded = initialTimelineExpanded
        self.showsResumePrompt = showsResumePrompt
        self.showsLoadFailure = showsLoadFailure
    }

    // EXPLORATORY: 两个 ornament 与窗口边缘的统一间距(同一值保证一致)。定稿后入 token。
    private let ornamentGap: CGFloat = DesignTokens.Spacing.lg
    private let ornamentHingeAngle: Double = 30
    // EXPLORATORY: 入场动画参数——从上方滑入的位移、整段曲线、卸载延迟(等关闭动画放完)。
    private let ornamentRevealOffset: CGFloat = 40
    private let ornamentRevealAnimation: Animation = DesignTokens.AnimationToken.panelSpring
    private let ornamentUnmountDelay: Duration = .seconds(0.5)

    var body: some View {
        scaledPlaybackBoundary
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(
                minWidth: Self.minimumContentSize.width,
                idealWidth: Self.idealContentSize.width,
                maxWidth: Self.maximumContentSize.width,
                minHeight: Self.minimumContentSize.height,
                idealHeight: Self.idealContentSize.height,
                maxHeight: Self.maximumContentSize.height
            )
            .frame(depth: 1)
            .background {
                WindowPlaybackSceneResizePreference(
                    idealSize: Self.idealContentSize,
                    minimumSize: Self.minimumContentSize,
                    maximumSize: Self.maximumContentSize
                )
                .allowsHitTesting(false)
            }
            // visibility 恒为 .visible、内容靠 mounted 条件挂载——避开系统淡入(那是
            // "瞬移"来源),入场/出场全由 revealed 手动驱动。
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.bottom),
                contentAlignment: Alignment3D(horizontal: .center, vertical: .top, depth: .back)
            ) {
                if deckMounted { deckOrnament }
            }
            .contentShape(.interaction, playbackShape)
            .onChange(of: isChromeVisible) { _, _ in
                updateDeckReveal()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("DesignComps-WindowPlaybackPage")
            .accessibilityLabel("Window playback preview")
    }

    // 出现:先挂载(此刻 revealed=false → opacity0 / 上移 / 平面),再同一段动画把 revealed
    // 推到 true(opacity / 位移 / 旋转一起跑,渐显贯穿全程)。消失:revealed→false 反向播放,
    // 放完再卸载。
    private func updateDeckReveal() {
        setReveal(
            show: isChromeVisible,
            mounted: { deckMounted = $0 },
            revealed: { deckRevealed = $0 },
            isStillHidden: { !isChromeVisible }
        )
    }

    private func setReveal(
        show: Bool,
        mounted: @escaping (Bool) -> Void,
        revealed: @escaping (Bool) -> Void,
        isStillHidden: @escaping () -> Bool
    ) {
        if show {
            // 先挂载并把视图渲染在隐藏初态(opacity0 / 上移 / 平面),下一帧再用动画推到
            // 完成态——保证出现是消失的严格反向,而不是新插入视图的"错乱"跳变。
            mounted(true)
            revealed(false)
            Task {
                try? await Task.sleep(for: .milliseconds(20))
                guard !isStillHidden() else { return }
                withAnimation(ornamentRevealAnimation) { revealed(true) }
            }
        } else {
            withAnimation(ornamentRevealAnimation) { revealed(false) }
            Task {
                try? await Task.sleep(for: ornamentUnmountDelay)
                if isStillHidden() { mounted(false) }
            }
        }
    }

    private var scaledPlaybackBoundary: some View {
        GeometryReader { proxy in
            let scale = Self.scale(for: proxy.size)

            playbackBoundary
                .frame(width: Self.designContentSize.width, height: Self.designContentSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var playbackBoundary: some View {
        ZStack {
            renderSurface
            chromeToggleTarget
            playbackChrome
                .opacity(isChromeVisible ? 1 : 0)
                .allowsHitTesting(isChromeVisible)
                .animation(DesignTokens.AnimationToken.controlsTransition, value: isChromeVisible)

            if showsResumePrompt {
                resumePromptOverlay
            }
            if showsLoadFailure {
                loadFailureOverlay
            }
        }
        .clipShape(playbackShape)
    }

    // 续播提示(UC-PLAY-02):播放前 overlay,主按钮续播 + 次按钮从头播。
    // 时间为占位 fixture。
    private var resumePromptOverlay: some View {
        PlaybackOverlayPanel(
            systemImage: "play.circle",
            title: "Resume Playback",
            message: "You stopped watching partway through.",
            primaryTitle: "Resume from 1:24:08",
            primaryIcon: "play.fill",
            secondaryTitle: "Play from Start",
            secondaryIcon: "backward.end.fill",
            identifierPrefix: "DesignComps-WindowPlaybackPage-resume"
        )
    }

    // 加载失败面板(UC-PLAY-23):原因描述 + Retry + Close。
    private var loadFailureOverlay: some View {
        PlaybackOverlayPanel(
            systemImage: "exclamationmark.triangle",
            title: "Failed to Load",
            message: "The video source is unreachable or the format isn't supported.",
            primaryTitle: "Retry",
            primaryIcon: "arrow.clockwise",
            secondaryTitle: "Close",
            secondaryIcon: "xmark",
            identifierPrefix: "DesignComps-WindowPlaybackPage-loadFailure"
        )
    }

    private var chromeToggleTarget: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleChromeVisibility)
            .accessibilityHidden(true)
    }

    // 视频窗口内只剩顶部返回/扩展;播放控件与设置面板都独立成 ornament。
    private var playbackChrome: some View {
        ZStack {
            controlMask
            VStack {
                topControls
                    .padding(DesignTokens.Spacing.xl)

                Spacer(minLength: 0)
            }
        }
    }

    // Bottom ornament 内容:融合播放面板(ADR-0009——设置由 ≡ 内联形变,不再单设前缘 ornament)。
    // EXPLORATORY: 初始与窗口共面,绕 X 轴(与底边平行)以贴窗口的 top 边为合页线朝用户
    // 抬起 30°;top padding(= ornamentGap)留出与窗口底缘的一致间距。
    private var deckOrnament: some View {
        FusedPlayerPanel(
            initialSettingsPresented: isSettingsPanelPresented,
            initialTimelineExpanded: initialTimelineExpanded
        )
        .rotation3DEffect(.degrees(deckRevealed ? ornamentHingeAngle : 0), axis: .x, anchor: .top)
        .padding(.top, ornamentGap)
        .opacity(deckRevealed ? 1 : 0)
        .offset(y: deckRevealed ? 0 : -ornamentRevealOffset)
    }

    private var renderSurface: some View {
        WindowPlaybackFixtureSurface()
            .accessibilityHidden(true)
            .accessibilityIdentifier("DesignComps-WindowPlaybackPage-renderSurface")
    }

    // 仅保留顶部遮罩(为返回/扩展按钮提供对比度);底部控件已移出视频成为 ornament,
    // 不再需要底部遮罩。
    private var controlMask: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        .black.opacity(0.40),
                        .black.opacity(0.18),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * topMaskHeightRatio)

                Spacer(minLength: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topControls: some View {
        HStack {
            GlassCircleIconButton(
                systemName: "chevron.left",
                accessibilityLabel: "Close playback window",
                action: {
                    dismissWindow(id: DesignPreviewNavigationModel.windowPlaybackWindowID)
                },
                accessibilityIdentifier: "DesignComps-WindowPlaybackPage-back"
            )

            Spacer(minLength: 0)

            GlassCircleIconButton(
                systemName: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "Expand playback window",
                accessibilityIdentifier: "DesignComps-WindowPlaybackPage-expand"
            )
        }
    }

    private var topMaskHeightRatio: CGFloat { 0.30 }
    private var bottomMaskHeightRatio: CGFloat { 0.36 }
    private var playbackShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.panel, style: .continuous)
    }

    private static func scale(for size: CGSize) -> CGFloat {
        min(size.width / designContentSize.width, size.height / designContentSize.height)
    }

    private func toggleChromeVisibility() {
        withAnimation(DesignTokens.AnimationToken.controlsTransition) {
            isChromeVisible.toggle()
        }
    }
}

private struct WindowPlaybackFixtureSurface: View {
    private static let fixtureAssetName = "WindowPlaybackDaylightAction"

    var body: some View {
        GeometryReader { proxy in
            Color.black
                .overlay {
                    Image(Self.fixtureAssetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .clipped()
        }
    }
}

// 播放前 / 加载失败的居中玻璃提示面板(UC-PLAY-02 / 23)。复用 ShapeToken.panel
// 玻璃、DesignTokens 排版/间距与 GlassCapsuleIconLabelButton 动作按钮;背景压暗用
// 既有 controlMask 同款黑色渐隐语义(此处为纯色 scrim)。
private struct PlaybackOverlayPanel: View {
    let systemImage: String
    let title: String
    let message: String
    let primaryTitle: String
    let primaryIcon: String
    let secondaryTitle: String
    let secondaryIcon: String
    let identifierPrefix: String

    var body: some View {
        ZStack {
            // Scrim:压暗播放画面以聚焦面板。EXPLORATORY: scrim 不透明度尚无专用 token,
            // 沿用 controlMask 的黑色遮罩语义。
            Rectangle()
                .fill(.black.opacity(0.40))
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: systemImage)
                    .font(DesignTokens.SymbolSize.hero)
                    .foregroundStyle(.white)

                Text(title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                Text(message)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .multilineTextAlignment(.center)

                HStack(spacing: DesignTokens.Spacing.md) {
                    GlassCapsuleIconLabelButton(
                        title: primaryTitle,
                        systemName: primaryIcon,
                        accessibilityLabel: primaryTitle,
                        accessibilityIdentifier: "\(identifierPrefix)-primary"
                    )
                    GlassCapsuleIconLabelButton(
                        title: secondaryTitle,
                        systemName: secondaryIcon,
                        accessibilityLabel: secondaryTitle,
                        accessibilityIdentifier: "\(identifierPrefix)-secondary"
                    )
                }
                .padding(.top, DesignTokens.Spacing.sm)
            }
            .padding(DesignTokens.Spacing.xxxl)
            .frame(maxWidth: DesignTokens.ProgressBar.previewWidth)
            .glassBackgroundEffect(in: DesignTokens.ShapeToken.panel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)-panel")
        .accessibilityLabel(title)
    }
}

private struct WindowPlaybackSceneResizePreference: UIViewControllerRepresentable {
    let idealSize: CGSize
    let minimumSize: CGSize
    let maximumSize: CGSize

    func makeUIViewController(context: Context) -> ResizePreferenceController {
        ResizePreferenceController(
            idealSize: idealSize,
            minimumSize: minimumSize,
            maximumSize: maximumSize
        )
    }

    func updateUIViewController(_ controller: ResizePreferenceController, context: Context) {
        controller.update(
            idealSize: idealSize,
            minimumSize: minimumSize,
            maximumSize: maximumSize
        )
    }

    final class ResizePreferenceController: UIViewController {
        private var idealSize: CGSize
        private var minimumSize: CGSize
        private var maximumSize: CGSize
        private var appliedSignature: ResizePreferenceSignature?

        init(idealSize: CGSize, minimumSize: CGSize, maximumSize: CGSize) {
            self.idealSize = idealSize
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPreferenceIfPossible()
        }

        func update(idealSize: CGSize, minimumSize: CGSize, maximumSize: CGSize) {
            self.idealSize = idealSize
            self.minimumSize = minimumSize
            self.maximumSize = maximumSize
            applyPreferenceIfPossible()
        }

        private func applyPreferenceIfPossible() {
            guard let windowScene = view.window?.windowScene else { return }

            let signature = ResizePreferenceSignature(
                idealSize: idealSize,
                minimumSize: minimumSize,
                maximumSize: maximumSize
            )
            guard appliedSignature != signature else { return }
            appliedSignature = signature

            windowScene.requestGeometryUpdate(
                .Vision(
                    size: idealSize,
                    minimumSize: minimumSize,
                    maximumSize: maximumSize,
                    resizingRestrictions: .uniform
                )
            )
        }
    }

    private struct ResizePreferenceSignature: Equatable {
        let idealSize: CGSize
        let minimumSize: CGSize
        let maximumSize: CGSize
    }
}

// === 审查用初始态预览(运行时仍是点按显隐 / 双击展开) ===

// 状态 B:设置面板 + 二级时间轴展开,并存。
#Preview("WP · Settings + timeline", windowStyle: .plain) {
    WindowPlaybackPage(
        initialChromeVisible: true,
        initialSettingsPanelPresented: true,
        initialTimelineExpanded: true
    )
}

// 状态 C:仅展开二级时间轴。
#Preview("WP · Timeline only", windowStyle: .plain) {
    WindowPlaybackPage(initialChromeVisible: true, initialTimelineExpanded: true)
}

// 状态 A:点击播放画面 → 召出 player panel(设置面板)。
#Preview("WP · Settings panel", windowStyle: .plain) {
    WindowPlaybackPage(initialChromeVisible: true, initialSettingsPanelPresented: true)
}

// 基础态:chrome 展开、控件折叠。
#Preview("WP · Controls", windowStyle: .plain) {
    WindowPlaybackPage(initialChromeVisible: true)
}

#Preview("Window Playback", windowStyle: .plain) {
    WindowPlaybackPage()
}

// 蓝图状态:续播提示(UC-PLAY-02)。
#Preview("WP · Resume prompt", windowStyle: .plain) {
    WindowPlaybackPage(showsResumePrompt: true)
}

// 蓝图状态:加载失败面板(UC-PLAY-23)。
#Preview("WP · Load failure", windowStyle: .plain) {
    WindowPlaybackPage(showsLoadFailure: true)
}
