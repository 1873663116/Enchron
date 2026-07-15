import SwiftUI

// MARK: - Preview routing

enum DesignPreviewPage: String, CaseIterable, Identifiable {
    // MARK: Components (front)
    case components
    case sidebar
    case settingListGroup
    case slider
    case environmentCard
    case connectionForm
    case dialogs
    case fusedPanel
    // MARK: Design Tokens (back)
    case spacing
    case radiusAndShapes
    case interactionAndLayout
    case typographyAndSymbols
    case surfaceAndStroke
    case animation
    case pressFeedback
    case componentStandards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .components: "Components"
        case .spacing: "Spacing"
        case .radiusAndShapes: "Radius & Shapes"
        case .interactionAndLayout: "Interaction & Layout"
        case .typographyAndSymbols: "Typography & Symbols"
        case .surfaceAndStroke: "Surface & Stroke"
        case .animation: "Animation"
        case .pressFeedback: "Press Feedback"
        case .sidebar: "Sidebar"
        case .settingListGroup: "Setting List Group"
        case .slider: "Slider"
        case .environmentCard: "Environment Card"
        case .connectionForm: "Connection Form"
        case .dialogs: "Dialogs"
        case .fusedPanel: "Fused Panel"
        case .componentStandards: "Component Standards"
        }
    }
}

struct ContentView: View {
    @State private var selection: DesignPreviewPage? = .components

    var body: some View {
        NavigationSplitView {
            List(DesignPreviewPage.allCases, selection: $selection) { page in
                Text(page.title)
                    .tag(page)
            }
            .navigationTitle("Design Preview")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            switch selection ?? .components {
            case .components:
                ComponentLibraryView()
            case .spacing:
                SpacingScalePreview()
            case .radiusAndShapes:
                RadiusShapesPreview()
            case .interactionAndLayout:
                InteractionLayoutPreview()
            case .typographyAndSymbols:
                TypographySymbolsPreview()
            case .surfaceAndStroke:
                SurfaceStrokePreview()
            case .animation:
                AnimationTokensPreview()
            case .pressFeedback:
                PressFeedbackPreview()
            case .sidebar:
                SidebarPreview()
            case .settingListGroup:
                SettingListGroupPreview()
            case .slider:
                SliderPreview()
            case .environmentCard:
                EnvironmentCardPreview()
            case .connectionForm:
                ConnectionFormPreview()
            case .dialogs:
                DialogsPreview()
            case .fusedPanel:
                FusedPlayerPanelPreview()
            case .componentStandards:
                ComponentStandardsPreview()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}

// MARK: - Fused Player Panel

struct FusedPlayerPanelPreview: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            FusedPlayerPanel()
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Fused Panel")
    }
}


// MARK: - Sidebar

struct SidebarPreview: View {
    var body: some View {
        ScrollView {
            SourceSidebarSection()
                .padding(DesignTokens.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Sidebar")
    }
}

// MARK: - Setting list group

struct SettingListGroupPreview: View {
    @State private var showClearCacheConfirm = false
    @State private var selectedSpecialCardID = "day"
    @State private var specialSliderValue = 0
    @State private var specialAuto = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("Setting List Group")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    SettingListGroup(items: [
                        .init(
                            title: "Display",
                            systemName: "display",
                            detail: "Tune brightness, colour profile, and how the playback window scales when you move it closer or further away.",
                            expansion: .top
                        ),
                        .init(
                            title: "Spatial Audio",
                            systemName: "speaker.wave.3",
                            detail: "Render sound that stays anchored to the screen as you look around, with head tracking applied to every channel.",
                            expansion: .center
                        ),
                        .init(
                            title: "Subtitles",
                            systemName: "captions.bubble",
                            detail: "Pick a default language, sizing, and background style for captions, applied across every video you open.",
                            expansion: .bottom
                        ),
                    ])
                    .frame(width: 580)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("Special Controls")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(.primary)

                        SettingListGroup(items: [
                            .init(
                                id: "special-card-selection",
                                title: "Scene",
                                accessory: .none,
                                embeddedControl: .cardSelection(
                                    options: [
                                        .init(id: "day", title: "Day", systemName: "sun.max.fill"),
                                        .init(id: "night", title: "Night", systemName: "moon.stars.fill"),
                                    ],
                                    selectedID: $selectedSpecialCardID
                                )
                            ),
                            .init(
                                id: "special-center-slider",
                                title: "Curve",
                                accessory: .none,
                                embeddedControl: .centerSlider(
                                    value: $specialSliderValue,
                                    leadingSystemImage: "rectangle",
                                    trailingSystemImage: "capsule",
                                    accessibilityLabel: "Curve"
                                )
                            ),
                            .init(
                                id: "special-plain-list",
                                title: "Auto",
                                accessory: .boundToggle(isOn: $specialAuto, isEnabled: true, marker: nil)
                            ),
                        ])
                        .frame(width: 720)
                    }

                    SettingListGroup(items: [
                        .init(
                            title: "Copy Diagnostic Summary",
                            systemName: "doc.on.doc",
                            accessory: .action(
                                title: "Copy",
                                feedback: "Copied",
                                systemName: "doc.on.doc",
                                role: .normal,
                                action: {}
                            )
                        ),
                    ])
                    .frame(width: 580)

                    SettingListGroup(items: [
                        .init(
                            title: "Logging Level",
                            systemName: "list.bullet.rectangle",
                            accessory: .menu(
                                title: "Info",
                                options: [
                                    .init("Off"),
                                    .init("Info"),
                                    .init("Debug"),
                                    .init("Trace"),
                                ]
                            )
                        ),
                        .init(
                            title: "Run Media Diagnostics",
                            systemName: "waveform.path.ecg",
                            accessory: .action(
                                title: "Run",
                                feedback: "Queued",
                                systemName: "play.fill",
                                role: .normal,
                                action: {}
                            )
                        ),
                        .init(
                            title: "Clear App Cache",
                            systemName: "trash",
                            accessory: .action(
                                title: "Clear",
                                feedback: nil,
                                systemName: nil,
                                role: .destructive,
                                action: { showClearCacheConfirm = true }
                            )
                        )
                    ])
                    .frame(width: 580)

                    SettingListGroup(items: [
                        .init(
                            title: "Performance HUD",
                            systemName: "gauge",
                            accessory: .toggle(isOn: false)
                        ),
                        .init(
                            title: "Cache Size",
                            systemName: "internaldrive",
                            accessory: .value("1.8 GB")
                        ),
                        .init(
                            title: "Version & Build",
                            systemName: "info.circle",
                            accessory: .valueAction(
                                value: "0.1.0 (42)",
                                actionTitle: "Copy",
                                feedback: "Copied",
                                action: {}
                            )
                        ),
                        .init(
                            title: "Current Media Inspector",
                            systemName: "list.bullet.rectangle",
                            keyValueDetail: [
                                .init(key: "Codec", value: "HEVC Main10"),
                                .init(key: "Resolution", value: "3840 x 2160"),
                                .init(key: "HDR", value: "HDR10 metadata detected")
                            ],
                            expansion: .top,
                            accessory: .automatic
                        )
                    ])
                    .frame(width: 580)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("File List Group")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(.primary)

                        FileListGroup(items: [
                            .folder(title: "Movies", itemCount: 24),
                            .folder(title: "Spatial", itemCount: 12),
                            .video(title: "Interstellar", fileSize: "8.2 GB", duration: "2:49:00", badges: ["HDR10+"]),
                            .video(title: "Blade Runner 2049", fileSize: "45.6 GB", duration: "2:29:55", badges: ["MV-HEVC"])
                        ])
                        .frame(width: 580)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Setting List Group")
        .enchronDestructiveConfirmation(
            "Clear App Cache?",
            message: "This removes thumbnails and temporary cache. It does not delete video files or playback history.",
            confirmTitle: "Clear",
            isPresented: $showClearCacheConfirm,
            onConfirm: {}
        )
    }
}


// MARK: - Slider

// 两种滑块的真相展示面:CenterSlider(居中档位)与 range-aware 的 RangeSlider
// (真实数值域 + 数值读出)。
struct SliderPreview: View {
    @State private var exposure = 0
    @State private var fineAdjust = -2
    @State private var peakPercentile = 99.9
    @State private var targetPeak = 406.0
    @State private var saturation = 9.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                centerSliderSection
                rangeSliderSection
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Slider")
    }

    private var centerSliderSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Center Slider")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(.primary)
            Text("居中档位、-5…5、Binding<Int>;无内置数值读出。")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)

            centerRow(
                "Exposure",
                value: $exposure,
                leading: "sun.min",
                trailing: "sun.max"
            )

            centerRow(
                "Fine Adjust",
                value: $fineAdjust,
                leading: "minus",
                trailing: "plus"
            )
        }
    }

    private var rangeSliderSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Slider")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(.primary)
            Text("range-aware、连续、Binding<Double>;按真实数值域映射 + 数值读出(可带小数 / 单位)。")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)

            rangeRow(
                "峰值百分位",
                value: $peakPercentile,
                range: 90...100,
                decimals: 1
            )
            rangeRow(
                "目标峰值亮度",
                value: $targetPeak,
                range: 100...2000,
                unit: "nits"
            )
            rangeRow(
                "饱和度",
                value: $saturation,
                range: -100...100
            )
        }
    }

    private func centerRow(
        _ title: String,
        value: Binding<Int>,
        leading: String,
        trailing: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Review-only readout; the component itself never shows a number.
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                Text(value.wrappedValue > 0 ? "+\(value.wrappedValue)" : "\(value.wrappedValue)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            CenterSlider(
                value: value,
                leadingSystemImage: leading,
                trailingSystemImage: trailing,
                accessibilityLabel: title,
                accessibilityIdentifier: "DesignPreview-CenterSlider-\(title)"
            )
        }
    }

    // 裸 RangeSlider 不渲染读出(读出在 SettingListRangeSliderRow 里);这里加一段
    // review-only 读出,让真实数值域 / 小数 / 单位在组件库里可见。
    private func rangeRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        decimals: Int = 0,
        unit: String? = nil
    ) -> some View {
        let readout = value.wrappedValue.formatted(.number.precision(.fractionLength(decimals)))
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("\(title) · \(Int(range.lowerBound))–\(Int(range.upperBound))")
                    .font(DesignTokens.Typography.headline)
                Text(unit.map { "\(readout) \($0)" } ?? readout)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            RangeSlider(
                value: value,
                range: range,
                accessibilityLabel: title,
                accessibilityValue: unit.map { "\(readout) \($0)" } ?? readout,
                accessibilityIdentifier: "DesignPreview-RangeSlider-\(title)"
            )
        }
    }
}

// MARK: - Environment card

struct EnvironmentCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                EnvironmentCard()
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Environment Card")
    }
}

// MARK: - Dialogs

// enchron alert 模式族的真相展示面:两个 modifier 各一个触发按钮,点按弹出对应
// alert。两者同为系统 `.alert` 表面、无 authored color;破坏性确认走
// ButtonRole.destructive 自动红,错误对话框是非破坏性双动作。
struct DialogsPreview: View {
    @State private var showsDestructive = false
    @State private var showsError = false
    @State private var lastAction = "未触发"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                dialogRow(
                    title: "Destructive Confirmation",
                    subtitle: "enchronDestructiveConfirmation · 标题+描述 · Cancel 固定 · Confirm 走 ButtonRole.destructive 自动红",
                    buttonTitle: "Clear Cache",
                    identifier: "DesignPreview-Dialogs-trigger-destructive"
                ) {
                    showsDestructive = true
                }

                dialogRow(
                    title: "Error Dialog",
                    subtitle: "enchronErrorDialog · 非破坏性双动作 · 主动作(Retry)+ 取消动作(OK)",
                    buttonTitle: "Trigger Error",
                    identifier: "DesignPreview-Dialogs-trigger-error"
                ) {
                    showsError = true
                }

                Text("最近动作:\(lastAction)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Dialogs")
        .enchronDestructiveConfirmation(
            "Clear Cache?",
            message: "This frees up disk space. Downloaded files and history aren't affected.",
            confirmTitle: "Clear",
            isPresented: $showsDestructive,
            onConfirm: { lastAction = "Destructive · Clear" }
        )
        .enchronErrorDialog(
            "File Browser Error",
            message: "Couldn't load this location. Check the source connection and try again.",
            primaryTitle: "Retry",
            secondaryTitle: "OK",
            isPresented: $showsError,
            identifierPrefix: "DesignPreview-Dialogs-error",
            onPrimary: { lastAction = "Error · Retry" },
            onSecondary: { lastAction = "Error · OK" }
        )
    }

    private func dialogRow(
        title: String,
        subtitle: String,
        buttonTitle: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(identifier)
        }
    }
}

// MARK: - Connection form

/// 连接协议。单组件靠它决定字段集合与地址校验规则。
enum ConnectionKind: String, CaseIterable, Identifiable {
    case smb
    case webdav

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smb: "SMB"
        case .webdav: "WebDAV"
        }
    }

    var subtitle: String {
        switch self {
        case .smb: "局域网共享 · 主机名或 IP"
        case .webdav: "HTTP(S) 服务器 · 完整地址"
        }
    }

    var systemImage: String {
        switch self {
        case .smb: "externaldrive.connected.to.line.below"
        case .webdav: "network"
        }
    }

    var addressLabel: String {
        switch self {
        case .smb: "地址"
        case .webdav: "服务器地址"
        }
    }

    var addressPlaceholder: String {
        switch self {
        case .smb: "192.168.1.10 或 mynas.local"
        case .webdav: "https://dav.example.com/remote.php/dav"
        }
    }
}

/// 连接生命周期的视觉状态。由 mock 驱动,供审查各状态外观。
/// 连接生命周期状态,由面板内的 mock 状态机驱动。
enum ConnectionMockState {
    case idle
    case connecting
    case error
    case timeout
    case success
}

/// EXPLORATORY: 带标签 / 焦点态 / 错误态的表单输入字段。
/// 组件库尚无此视觉形态——已上报人类裁决,暂以探索稿形态存在。
struct ConnectionFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var accessibilityIdentifier: String

    @FocusState private var isFocused: Bool

    // EXPLORATORY: 字段外形未进 token——12pt 圆角、44pt 高沿用现有 Radius.small /
    // Interactive.regular;焦点描边复用 Surface.focusBorder。
    private let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.supportingText)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .focused($isFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .hoverEffectDisabled()
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Interactive.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(shape)
            .glassBackgroundEffect(in: shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.automatic)
            .contentShape(shape)
            .overlay {
                shape
                    .strokeBorder(
                        isFocused ? DesignTokens.Surface.focusBorder : .clear,
                        lineWidth: DesignTokens.Stroke.bold
                    )
                    .animation(DesignTokens.AnimationToken.selection, value: isFocused)
            }
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(label)
        }
    }
}

struct ConnectionFormPanel: View {
    let kind: ConnectionKind
    var onDismiss: () -> Void = {}

    // 预填的默认值同时也是「正确」连接信息:开箱即可点成功,改错可测失败路径。
    @State private var address = ConnectionFormPanel.correctAddress
    @State private var username = ConnectionFormPanel.correctUsername
    @State private var password = ConnectionFormPanel.correctPassword
    @State private var connectAsGuest = false   // SMB 专属:默认关闭,常显账号密码
    @State private var state: ConnectionMockState = .idle
    @State private var connectTask: Task<Void, Never>?

    // EXPLORATORY: 面板宽度与状态色未进 token。绿色成功 / 橙色超时 / 红色失败
    // 是 mockup 临时色;提升前需新增语义 token 或复用既有色。
    private let panelWidth: CGFloat = 420
    private let shape = DesignTokens.ShapeToken.card

    // EXPLORATORY: mock 正确连接信息与计时常量,非真实凭证、非真实超时。
    private static let correctAddress = "192.168.1.1"
    private static let correctUsername = "123"
    private static let correctPassword = "123"
    private let connectWaitDuration: Duration = .seconds(3)
    private let successHoldDuration: Duration = .seconds(1)
    // 账密揭示相对容器/按钮的滞后量。
    private let credentialRevealDelay: Double = 0.18

    private var showsCredentials: Bool {
        switch kind {
        case .smb: !connectAsGuest
        case .webdav: true
        }
    }

    /// 连接中或成功(待自动关闭)期间,锁定整个输入区。
    private var isBusy: Bool {
        state == .connecting || state == .success
    }

    /// 访客模式不要求账密;其余情况账密必填。
    private var credentialsRequired: Bool {
        !(kind == .smb && connectAsGuest)
    }

    private var inputsComplete: Bool {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if credentialsRequired {
            return !username.isEmpty && !password.isEmpty
        }
        return true
    }

    private var connectDisabled: Bool {
        isBusy || !inputsComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header
            fields
            statusRegion
            actions
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(width: panelWidth, alignment: .leading)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        // 动画挂在整个面板根部:容器/按钮高度按同一条曲线立即联动;
        // 账密块靠自身延迟过渡滞后浮现(见 credentialsTransition)。
        .animation(DesignTokens.AnimationToken.selection, value: showsCredentials)
        .animation(DesignTokens.AnimationToken.selection, value: state)
        .onDisappear { connectTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: kind.systemImage)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Theme.accent)
                .frame(width: DesignTokens.Interactive.regular)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("连接到 \(kind.title)")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.primary)
                Text(kind.subtitle)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
            }
            Spacer(minLength: 0)
        }
    }

    // 账号密码显隐过渡,对齐 SettingListGroup「Current Media Inspector」展开:
    // 从顶部 scale 0.96 + opacity 长出,opacity 收起。
    // 插入带 credentialRevealDelay:容器/按钮已挂根部动画立即就位,
    // 字段滞后浮现,形成「框先动、账密后现」的异步观感。
    private var credentialsTransition: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.scale(scale: 0.96, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .move(edge: .top))
                .animation(DesignTokens.AnimationToken.selection.delay(credentialRevealDelay)),
            removal: AnyTransition.opacity
                .animation(DesignTokens.AnimationToken.selection)
        )
    }

    @ViewBuilder
    private var credentialFields: some View {
        ConnectionFormField(
            label: "用户名",
            placeholder: "用户名",
            text: $username,
            accessibilityIdentifier: "DesignPreview-connection-\(kind.rawValue)-username"
        )
        ConnectionFormField(
            label: "密码",
            placeholder: "密码",
            text: $password,
            isSecure: true,
            accessibilityIdentifier: "DesignPreview-connection-\(kind.rawValue)-password"
        )
    }

    private var guestToggle: some View {
        Toggle("以访客身份连接", isOn: $connectAsGuest)
            .font(DesignTokens.Typography.selectionHeader)
            .tint(DesignTokens.Theme.accent)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            ConnectionFormField(
                label: kind.addressLabel,
                placeholder: kind.addressPlaceholder,
                text: $address,
                accessibilityIdentifier: "DesignPreview-connection-\(kind.rawValue)-address"
            )

            if showsCredentials {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    credentialFields
                }
                .transition(credentialsTransition)
            }

            // 访客开关在账号密码下方。
            if kind == .smb {
                guestToggle
            }
        }
        // 连接中/成功期间锁定地址、账密与访客开关,避免中途改动。
        .disabled(isBusy)
    }

    @ViewBuilder
    private var statusRegion: some View {
        Group {
            switch state {
            case .idle:
                EmptyView()
            case .connecting:
                HStack(spacing: DesignTokens.Spacing.sm) {
                    LoadingSpinner(size: DesignTokens.Interactive.compact)
                    Text("正在连接…")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
            case .error:
                statusLine(systemImage: "exclamationmark.triangle.fill",
                           text: "连接失败:认证被拒绝,请检查用户名和密码",
                           tint: .red)
            case .timeout:
                statusLine(systemImage: "clock.badge.exclamationmark",
                           text: "连接超时:无法访问该地址,请检查网络",
                           tint: .orange)
            case .success:
                statusLine(systemImage: "checkmark.circle.fill",
                           text: "连接成功",
                           tint: DesignTokens.Theme.accent)
            }
        }
        // 连接中 / 警告 / 成功的出现都从顶部淡入,而非瞬现。
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // EXPLORATORY: 状态行临时色直接取 .red/.orange 与 accent,未抽 token。
    private func statusLine(systemImage: String, text: String, tint: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
            Spacer(minLength: 0)
            GlassCapsuleIconLabelButton(
                title: "取消",
                systemName: "xmark",
                accessibilityLabel: "取消",
                action: cancelAndDismiss,
                accessibilityIdentifier: "DesignPreview-connection-\(kind.rawValue)-cancel"
            )
            GlassCapsuleIconLabelButton(
                title: "连接",
                systemName: "link",
                accessibilityLabel: "连接",
                action: connect,
                accessibilityIdentifier: "DesignPreview-connection-\(kind.rawValue)-connect"
            )
            .opacity(connectDisabled ? 0.5 : 1)
            .disabled(connectDisabled)
        }
    }

    // MARK: - Preview state

    /// 点连接:进入 3s 等待,期满后判定结果。
    private func connect() {
        connectTask?.cancel()
        state = .connecting
        connectTask = Task {
            try? await Task.sleep(for: connectWaitDuration)
            guard !Task.isCancelled else { return }
            resolveOutcome()
        }
    }

    /// 判定优先级:地址不可达(超时)→ 凭证错误(报错)→ 成功。
    private func resolveOutcome() {
        let addressOK = address.trimmingCharacters(in: .whitespaces) == Self.correctAddress
        let credentialsOK: Bool = {
            // 访客模式不带认证,只看地址。
            if kind == .smb && connectAsGuest { return true }
            return username == Self.correctUsername && password == Self.correctPassword
        }()

        if !addressOK {
            state = .timeout
        } else if !credentialsOK {
            state = .error
        } else {
            state = .success
            scheduleAutoDismiss()
        }
    }

    /// 成功后停留片刻让用户看清,再自动关闭。
    private func scheduleAutoDismiss() {
        connectTask?.cancel()
        connectTask = Task {
            try? await Task.sleep(for: successHoldDuration)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    /// 取消:撤销挂起任务并立即关闭。
    private func cancelAndDismiss() {
        connectTask?.cancel()
        onDismiss()
    }
}

struct ConnectionFormPreview: View {
    @State private var smbPresented = true
    @State private var webdavPresented = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Connection Form")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.primary)
                    Text("默认预填正确连接信息(192.168.1.1 / 123 / 123)。点连接 → 等 3s → 成功后自动关闭;改错地址出超时、改错账密出报错;取消随时关闭。关闭后用「重新打开」复看。")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }

                HStack(alignment: .top, spacing: DesignTokens.Spacing.xxl) {
                    panelColumn(kind: .smb, presented: $smbPresented)
                    panelColumn(kind: .webdav, presented: $webdavPresented)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Connection Form")
    }

    private func panelColumn(
        kind: ConnectionKind,
        presented: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if presented.wrappedValue {
                ConnectionFormPanel(kind: kind, onDismiss: { presented.wrappedValue = false })
                    // EXPLORATORY: 消失动画——缩小 + 淡出,临时 scale 值。
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                GlassCapsuleIconLabelButton(
                    title: "重新打开 \(kind.title)",
                    systemName: "arrow.clockwise",
                    accessibilityLabel: "重新打开 \(kind.title)",
                    action: { presented.wrappedValue = true },
                    accessibilityIdentifier: "DesignPreview-connection-\(kind.rawValue)-reopen"
                )
            }
        }
        .frame(width: 420, alignment: .top)
        .animation(DesignTokens.AnimationToken.panelSpring, value: presented.wrappedValue)
    }
}

// MARK: - Token pages

private struct TokenPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                content
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
    }
}

private func valueString(_ value: CGFloat) -> String {
    if value == .greatestFiniteMagnitude {
        return "full"
    }
    return String(format: "%.1fpt", value)
}

// MARK: - Token spec row (unified token display)

/// One token rendered as a single row: a visual `swatch`, its `leafName` and
/// `value`, and a usage `note`. Replaces the old "demo block + mono table"
/// split — the swatch and its data share one row, and the `DesignTokens.X.`
/// namespace prefix is shown once per section (on `TokenSpecSection`) instead
/// of repeated on every row.
struct TokenSpec: Identifiable {
    let id = UUID()
    let leafName: String
    let value: String
    let note: String
    let swatch: AnyView?

    /// A token with a visual representation (size, colour, shape, glyph).
    static func spec(
        _ leafName: String,
        _ value: String,
        _ note: String,
        @ViewBuilder swatch: () -> some View
    ) -> TokenSpec {
        TokenSpec(leafName: leafName, value: value, note: note, swatch: AnyView(swatch()))
    }

    /// A pure scalar/relationship token with no visual (e.g. `inactiveScale =
    /// 0.66`). The swatch column stays empty so rows stay aligned.
    static func scalar(_ leafName: String, _ value: String, _ note: String) -> TokenSpec {
        TokenSpec(leafName: leafName, value: value, note: note, swatch: nil)
    }
}

private struct TokenSpecRowView: View {
    let spec: TokenSpec
    let swatchWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            ZStack {
                if let swatch = spec.swatch {
                    swatch
                }
            }
            .frame(width: swatchWidth, height: swatchWidth)

            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(spec.leafName)
                    .font(.system(.callout, design: .monospaced))
                Text(spec.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .leading)

            Text(spec.note)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(minHeight: swatchWidth + DesignTokens.Spacing.md, alignment: .center)
    }
}

/// A grouped, divider-separated list of token specs on the shared list-group
/// glass surface — the same visual language as `SettingListGroup`/`FileListGroup`.
struct TokenSpecGroup: View {
    let specs: [TokenSpec]
    var swatchWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                if index > 0 {
                    SettingListGroupDivider()
                }
                TokenSpecRowView(spec: spec, swatchWidth: swatchWidth)
            }
        }
        .enchronListGroupSurface(cornerRadius: DesignTokens.Radius.element)
    }
}

/// A token section: an uppercase title with the namespace prefix shown once,
/// an optional `hero` demo (for tokens too large to fit a row swatch, e.g.
/// `playerControlsWidth`), and the spec group.
struct TokenSpecSection<Hero: View>: View {
    let title: String
    let namespace: String
    let specs: [TokenSpec]
    let hero: Hero

    init(
        title: String,
        namespace: String,
        specs: [TokenSpec],
        @ViewBuilder hero: () -> Hero = { EmptyView() }
    ) {
        self.title = title
        self.namespace = namespace
        self.specs = specs
        self.hero = hero()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(namespace)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if !(hero is EmptyView) {
                hero
                    .padding(.bottom, DesignTokens.Spacing.xs)
            }

            TokenSpecGroup(specs: specs)
        }
    }
}

// MARK: - Token swatches (reusable across token pages)

/// A filled accent circle of diameter `size`, nested inside a dashed reference
/// ring, so interactive/symbol sizes read at true scale against a common 64pt frame.
@ViewBuilder
private func tokenSizeSwatch(_ size: CGFloat, reference: CGFloat = 64) -> some View {
    ZStack {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: DesignTokens.Stroke.regular, dash: [4, 3]))
            .foregroundStyle(.tertiary)
            .frame(width: reference, height: reference)
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: min(size, reference), height: min(size, reference))
    }
}

/// A proportional accent bar — `value` mapped against `max` into a 56pt track.
@ViewBuilder
private func tokenBarSwatch(_ value: CGFloat, max maxValue: CGFloat, height: CGFloat = 16) -> some View {
    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        .fill(Color.accentColor.opacity(0.45))
        .frame(width: Swift.max(Swift.min(value / maxValue * 56, 56), 6), height: height)
}

/// A colour chip with a subtle border, for opacity/colour tokens.
@ViewBuilder
private func tokenColorSwatch(_ color: Color) -> some View {
    let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
    shape
        .fill(color)
        .frame(width: 40, height: 40)
        .overlay {
            shape.stroke(DesignTokens.Surface.divider, lineWidth: DesignTokens.Stroke.subtle)
        }
}

/// A filled rounded square showing a corner radius (capsule for `full`).
@ViewBuilder
private func tokenRadiusSwatch(_ radius: CGFloat) -> some View {
    if radius == .greatestFiniteMagnitude {
        let shape = Capsule()
        shape
            .fill(DesignTokens.Surface.elevated)
            .frame(width: 56, height: 36)
            .overlay { shape.strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular) }
    } else {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(DesignTokens.Surface.elevated)
            .frame(width: 56, height: 56)
            .overlay { shape.strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular) }
    }
}

/// A filled sample of a shape token.
@ViewBuilder
private func tokenShapeSwatch(_ shape: some Shape) -> some View {
    shape
        .fill(DesignTokens.Surface.elevated)
        .frame(width: 56, height: 56)
        .overlay { shape.stroke(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular) }
}

/// A bordered rectangle drawn at a given stroke width.
@ViewBuilder
private func tokenStrokeSwatch(_ width: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: width)
        .frame(width: 56, height: 44)
}

/// The glyph "Ag" set in a typography token, so weight/size read directly.
@ViewBuilder
private func tokenTypographySwatch(_ font: Font) -> some View {
    Text("Ag").font(font)
}

/// Two nested rectangles showing how far a press-feedback scale shrinks a shape.
@ViewBuilder
private func tokenScaleSwatch(_ scale: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
    ZStack {
        shape.stroke(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.subtle)
            .frame(width: 48, height: 40)
        shape.fill(Color.accentColor.opacity(0.4))
            .frame(width: 48 * scale, height: 40 * scale)
    }
}

/// A small bar that animates open/closed on tap — a per-row "tap to replay"
/// sample for animation tokens.
private struct AnimationSampleSwatch: View {
    let name: String
    let animation: Animation
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(animation) { expanded.toggle() }
        } label: {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(expanded ? Color.accentColor.opacity(0.65) : DesignTokens.Surface.elevated)
                .frame(width: expanded ? 56 : 22, height: 22)
                .frame(width: 56, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-Tokens-animation-\(name)")
        .accessibilityLabel("Replay \(name) animation")
    }
}

// MARK: - Spacing

struct SpacingScalePreview: View {
    private var specs: [TokenSpec] {
        [
            .spec("xxs", "4pt", "hover gap, micro adjustment") {
                tokenBarSwatch(DesignTokens.Spacing.xxs, max: 48, height: 20)
            },
            .spec("xs", "8pt", "compact padding, icon gaps") {
                tokenBarSwatch(DesignTokens.Spacing.xs, max: 48, height: 20)
            },
            .spec("sm", "12pt", "medium padding, list item spacing") {
                tokenBarSwatch(DesignTokens.Spacing.sm, max: 48, height: 20)
            },
            .spec("md", "16pt", "standard padding") {
                tokenBarSwatch(DesignTokens.Spacing.md, max: 48, height: 20)
            },
            .spec("lg", "20pt", "panel padding, section spacing") {
                tokenBarSwatch(DesignTokens.Spacing.lg, max: 48, height: 20)
            },
            .spec("xl", "24pt", "large gaps") {
                tokenBarSwatch(DesignTokens.Spacing.xl, max: 48, height: 20)
            },
            .spec("xxl", "32pt", "section dividers") {
                tokenBarSwatch(DesignTokens.Spacing.xxl, max: 48, height: 20)
            },
            .spec("xxxl", "48pt", "extra-large margins") {
                tokenBarSwatch(DesignTokens.Spacing.xxxl, max: 48, height: 20)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Spacing") {
            TokenSpecSection(
                title: "Spacing Scale",
                namespace: "DesignTokens.Spacing.*",
                specs: specs
            )
        }
    }
}

// MARK: - Radius & shapes

struct RadiusShapesPreview: View {
    private var radiusSpecs: [TokenSpec] {
        [
            .spec("panel", "40pt", "large panels, settings pages, detail views") {
                tokenRadiusSwatch(DesignTokens.Radius.panel)
            },
            .spec("card", "32pt", "cards, menus, mid-level containers") {
                tokenRadiusSwatch(DesignTokens.Radius.card)
            },
            .spec("element", "24pt", "menu items, toolbar, inner containers") {
                tokenRadiusSwatch(DesignTokens.Radius.element)
            },
            .spec("small", "12pt", "tags, thumbnails, small rounded backgrounds") {
                tokenRadiusSwatch(DesignTokens.Radius.small)
            },
            .spec("full", "full", "circles and capsules") {
                tokenRadiusSwatch(.greatestFiniteMagnitude)
            },
            .scalar("concentric", "function", "inner radius = outer radius − padding"),
        ]
    }

    private var shapeSpecs: [TokenSpec] {
        [
            .spec("panel", "radius 40", "large panel shape") {
                tokenShapeSwatch(DesignTokens.ShapeToken.panel)
            },
            .spec("card", "radius 32", "card and menu container shape") {
                tokenShapeSwatch(DesignTokens.ShapeToken.card)
            },
            .spec("element", "radius 24", "menu item and toolbar shape") {
                tokenShapeSwatch(DesignTokens.ShapeToken.element)
            },
        ]
    }

    private var concentricSpecs: [TokenSpec] {
        [
            .spec("panel → card", "40 − 8 = 32", "panel containing a card") {
                concentricSwatch(outer: DesignTokens.Radius.panel, inner: DesignTokens.Radius.card)
            },
            .spec("card → element", "32 − 8 = 24", "menu containing a row") {
                concentricSwatch(outer: DesignTokens.Radius.card, inner: DesignTokens.Radius.element)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Radius & Shapes") {
            TokenSpecSection(
                title: "Radius Tokens",
                namespace: "DesignTokens.Radius.*",
                specs: radiusSpecs
            )

            TokenSpecSection(
                title: "Shape Tokens",
                namespace: "DesignTokens.ShapeToken.*",
                specs: shapeSpecs
            )

            TokenSpecSection(
                title: "Concentric Examples",
                namespace: "outer − padding → inner",
                specs: concentricSpecs
            )
        }
    }

    @ViewBuilder
    private func concentricSwatch(outer: CGFloat, inner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: outer, style: .continuous)
                .fill(DesignTokens.Surface.card)
                .frame(width: 60, height: 56)
            RoundedRectangle(cornerRadius: inner, style: .continuous)
                .fill(DesignTokens.Surface.overlay)
                .frame(width: 44, height: 40)
        }
    }
}

// MARK: - Interaction & layout

struct InteractionLayoutPreview: View {
    private var interactiveSpecs: [TokenSpec] {
        [
            .spec("mini", "28pt", "disclosure, auxiliary controls") {
                tokenSizeSwatch(DesignTokens.Interactive.mini)
            },
            .spec("compact", "36pt", "compact scrubbers and dense icon controls") {
                tokenSizeSwatch(DesignTokens.Interactive.compact)
            },
            .spec("regular", "44pt", "standard buttons") {
                tokenSizeSwatch(DesignTokens.Interactive.regular)
            },
            .spec("large", "60pt", "navigation buttons, self-sufficient target") {
                tokenSizeSwatch(DesignTokens.Interactive.large)
            },
            .spec("xl", "64pt", "primary action") {
                tokenSizeSwatch(DesignTokens.Interactive.xl)
            },
            .spec("rowHeight", "60pt", "menu/list row minimum height") {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 52, height: 56)
            },
            .spec("buttonSpacing", "16pt", "minimum spacing between stacked buttons") {
                HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
                    Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 14, height: 14)
                    Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 14, height: 14)
                }
            },
        ]
    }

    private var layoutSpecs: [TokenSpec] {
        [
            .spec("playerControlsWidth", "680pt", "PlayerControlsView and NLETimelineView panel width") {
                tokenBarSwatch(DesignTokens.Layout.playerControlsWidth, max: 680)
            },
            .spec("ornamentGap", "20pt", "ornament overlap with window bottom edge") {
                tokenBarSwatch(DesignTokens.Layout.ornamentGap, max: 680)
            },
        ]
    }

    private var progressBarSpecs: [TokenSpec] {
        [
            .spec("thumbDiameter", "24pt", "standard draggable scrubber button") {
                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Theme.accent, lineWidth: DesignTokens.Stroke.bold)
                    }
                    .frame(width: DesignTokens.ProgressBar.thumbDiameter, height: DesignTokens.ProgressBar.thumbDiameter)
            },
            .spec("trackHeight", "24pt", "active drag track height") {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: 48, height: DesignTokens.ProgressBar.trackHeight)
            },
            .scalar("inactiveScale", "0.66", "unfocused and hover track height scale"),
            .spec("inactiveTrackHeight", "15.8pt", "track height before active drag") {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: 48, height: DesignTokens.ProgressBar.inactiveTrackHeight)
            },
            .spec("hitHeight", "60pt", "hover and drag target height") {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 28, height: 56)
            },
            .spec("previewWidth", "680pt", "Design Preview player progress width") {
                tokenBarSwatch(DesignTokens.ProgressBar.previewWidth, max: 680)
            },
            .scalar("timeBubbleOffset", "24pt", "time readout above scrubber"),
            .spec("playedColor", "white 0.72", "played portion in normal state") {
                tokenColorSwatch(.white.opacity(0.72))
            },
            .spec("unplayedColor", "white 0.16", "unplayed portion in normal state") {
                tokenColorSwatch(.white.opacity(0.16))
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Interaction & Layout") {
            TokenSpecSection(
                title: "Interactive Sizes",
                namespace: "DesignTokens.Interactive.*",
                specs: interactiveSpecs
            )

            TokenSpecSection(
                title: "Layout Dimensions",
                namespace: "DesignTokens.Layout.*",
                specs: layoutSpecs
            ) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    dimensionBar("playerControlsWidth", DesignTokens.Layout.playerControlsWidth, maxWidth: 680)
                    dimensionBar("ornamentGap", DesignTokens.Layout.ornamentGap, maxWidth: 220)
                }
            }

            TokenSpecSection(
                title: "Progress Bar",
                namespace: "DesignTokens.ProgressBar.*",
                specs: progressBarSpecs
            ) {
                FusedPlayerPanel()
            }
        }
    }

    private func dimensionBar(_ title: String, _ width: CGFloat, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(title)  \(Int(width))pt")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: min(width, maxWidth), height: 28)
        }
    }
}

// MARK: - Typography & symbols

struct TypographySymbolsPreview: View {
    private var typographySpecs: [TokenSpec] {
        [
            .spec("title", ".title2", "video titles, page headings") {
                tokenTypographySwatch(DesignTokens.Typography.title)
            },
            .spec("headline", ".headline", "card titles, section labels") {
                tokenTypographySwatch(DesignTokens.Typography.headline)
            },
            .spec("metadata", ".caption", "resolution, file size, date metadata") {
                tokenTypographySwatch(DesignTokens.Typography.metadata)
            },
            .spec("sectionHeader", ".caption2", "section headers") {
                tokenTypographySwatch(DesignTokens.Typography.sectionHeader)
            },
            .spec("badge", ".caption", "badge labels") {
                Text("HDR")
                    .font(DesignTokens.Typography.badge)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .enchronGlassBadge()
            },
            .spec("monospacedDetail", "9pt medium mono", "timecode and ruler text") {
                Text("12:34")
                    .font(DesignTokens.Typography.monospacedDetail)
                    .foregroundStyle(.secondary)
            },
        ]
    }

    private var symbolSpecs: [TokenSpec] {
        [
            .spec("control", "24pt semibold", "skip and seek buttons") {
                symbolGlyph(DesignTokens.SymbolSize.control)
            },
            .spec("card", "36pt", "card and folder icons") {
                symbolGlyph(DesignTokens.SymbolSize.card)
            },
            .spec("action", "36pt medium", "play/pause primary action") {
                symbolGlyph(DesignTokens.SymbolSize.action)
            },
            .spec("feature", "44pt", "environment selector and large UI icons") {
                symbolGlyph(DesignTokens.SymbolSize.feature)
            },
            .spec("hero", "48pt", "hero detail view icons") {
                symbolGlyph(DesignTokens.SymbolSize.hero)
            },
            .spec("giant", "60pt", "empty state placeholder icons") {
                symbolGlyph(DesignTokens.SymbolSize.giant)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Typography & Symbols") {
            TokenSpecSection(
                title: "Typography",
                namespace: "DesignTokens.Typography.*",
                specs: typographySpecs
            )

            TokenSpecSection(
                title: "Symbol Sizes",
                namespace: "DesignTokens.SymbolSize.*",
                specs: symbolSpecs
            )
        }
    }

    private func symbolGlyph(_ font: Font) -> some View {
        Image(systemName: "play.fill")
            .font(font)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Surface & stroke

struct SurfaceStrokePreview: View {
    private var surfaceSpecs: [TokenSpec] {
        [
            .spec("card", "white 0.03", "card background") {
                tokenColorSwatch(DesignTokens.Surface.card)
            },
            .spec("elevated", "white 0.04", "elevated panel background") {
                tokenColorSwatch(DesignTokens.Surface.elevated)
            },
            .spec("overlay", "white 0.06", "overlay / brighter surface") {
                tokenColorSwatch(DesignTokens.Surface.overlay)
            },
            .spec("selected", "white 0.08", "selected state background") {
                tokenColorSwatch(DesignTokens.Surface.selected)
            },
            .spec("border", "white 0.05", "subtle border") {
                tokenColorSwatch(DesignTokens.Surface.border)
            },
            .spec("focusBorder", "theme accent", "focused input/control border") {
                tokenColorSwatch(DesignTokens.Surface.focusBorder)
            },
        ]
    }

    private var strokeSpecs: [TokenSpec] {
        [
            .spec("subtle", "0.5pt", "card borders, unselected state") {
                tokenStrokeSwatch(DesignTokens.Stroke.subtle)
            },
            .spec("regular", "1.0pt", "timeline major ticks") {
                tokenStrokeSwatch(DesignTokens.Stroke.regular)
            },
            .spec("bold", "1.5pt", "playhead, selected state borders") {
                tokenStrokeSwatch(DesignTokens.Stroke.bold)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Surface & Stroke") {
            TokenSpecSection(
                title: "Surface Tiers",
                namespace: "DesignTokens.Surface.*",
                specs: surfaceSpecs
            )

            TokenSpecSection(
                title: "Stroke Widths",
                namespace: "DesignTokens.Stroke.*",
                specs: strokeSpecs
            )
        }
    }
}

// MARK: - Animation

struct AnimationTokensPreview: View {
    private var animationSpecs: [TokenSpec] {
        [
            .spec("controlsTransition", "easeInOut 0.4s", "controls show/hide") {
                AnimationSampleSwatch(name: "controlsTransition", animation: DesignTokens.AnimationToken.controlsTransition)
            },
            .spec("panelSpring", "spring 0.35 b0.15", "panel expand/collapse") {
                AnimationSampleSwatch(name: "panelSpring", animation: DesignTokens.AnimationToken.panelSpring)
            },
            .spec("menuPopup", "spring 0.35 b0.15", "menu/popover popup") {
                AnimationSampleSwatch(name: "menuPopup", animation: DesignTokens.AnimationToken.menuPopup)
            },
            .spec("selection", "bouncy 0.4 +0.1", "selection state change") {
                AnimationSampleSwatch(name: "selection", animation: DesignTokens.AnimationToken.selection)
            },
            .spec("playback", "spring r0.45 d0.85", "play/pause state") {
                AnimationSampleSwatch(name: "playback", animation: DesignTokens.AnimationToken.playback)
            },
            .spec("scene", "spring r0.3 d0.7", "cinema environment switch") {
                AnimationSampleSwatch(name: "scene", animation: DesignTokens.AnimationToken.scene)
            },
            .spec("fadeIn", "easeIn 0.25s", "content fade-in") {
                AnimationSampleSwatch(name: "fadeIn", animation: DesignTokens.AnimationToken.fadeIn)
            },
            .spec("skeleton", "easeInOut 1s repeat", "skeleton loading pulse") {
                AnimationSampleSwatch(name: "skeleton", animation: DesignTokens.AnimationToken.skeleton)
            },
        ]
    }

    private var spinnerSpecs: [TokenSpec] {
        [
            .scalar("headAnimation", "easeOut 0.7s", "spinner head extension"),
            .scalar("tailAnimation", "easeOut 0.55s", "spinner tail catch-up"),
            .scalar("headDuration", "700ms", "spinner head phase duration"),
            .scalar("tailDuration", "550ms", "spinner tail phase duration"),
        ]
    }

    var body: some View {
        TokenPage(title: "Animation") {
            TokenSpecSection(
                title: "Animation Tokens",
                namespace: "DesignTokens.AnimationToken.*  ·  tap to replay",
                specs: animationSpecs
            )

            TokenSpecSection(
                title: "Loading Spinner",
                namespace: "DesignTokens.LoadingSpinner.*",
                specs: spinnerSpecs
            ) {
                LoadingSpinner()
            }
        }
    }
}

// MARK: - Press feedback

struct PressFeedbackPreview: View {
    private var specs: [TokenSpec] {
        [
            .spec("card", "scale 0.97", "cards and broad spatial surfaces") {
                tokenScaleSwatch(DesignTokens.PressFeedback.card.pressedScale)
            },
            .spec("row", "scale 0.985", "menu rows and list items") {
                tokenScaleSwatch(DesignTokens.PressFeedback.row.pressedScale)
            },
            .spec("control", "scale 0.96", "control capsules and grouped controls") {
                tokenScaleSwatch(DesignTokens.PressFeedback.control.pressedScale)
            },
            .spec("icon", "scale 0.90", "individual icon targets, stronger return spring") {
                tokenScaleSwatch(DesignTokens.PressFeedback.icon.pressedScale)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Press Feedback") {
            TokenSpecSection(
                title: "Press Feedback Tokens",
                namespace: "DesignTokens.PressFeedback.*  ·  tap a shape to feel it",
                specs: specs
            ) {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                    pressCardPreview
                    pressRowPreview
                    pressControlPreview
                    pressIconPreview
                }
            }
        }
    }

    private var pressCardPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            GridCard.video(
                title: "Card",
                fileSize: scaleText(DesignTokens.PressFeedback.card),
                duration: DesignTokens.PressFeedback.card.holdDurationLabel,
                badges: ["CARD"]
            )
            Text("card · broad surface")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var pressRowPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {} label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text("Row")
                        .font(.body)
                    Spacer()
                    Text(scaleText(DesignTokens.PressFeedback.row))
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(width: 280, height: DesignTokens.Interactive.rowHeight)
                .enchronGlassMenuItem()
            }
            .buttonStyle(.plain)
            .enchronPressFeedback(.row)
            .accessibilityIdentifier("DesignPreview-PressFeedback-button-row")
            .accessibilityLabel("Preview row press feedback")

            Text("row · list item")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var pressControlPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {} label: {
                HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                    Image(systemName: "backward.fill")
                        .font(DesignTokens.SymbolSize.control)
                    Image(systemName: "play.fill")
                        .font(DesignTokens.SymbolSize.action)
                    Image(systemName: "forward.fill")
                        .font(DesignTokens.SymbolSize.control)
                }
                .foregroundStyle(.secondary)
                .frame(width: 180, height: DesignTokens.Interactive.large)
                .enchronGlassControl()
            }
            .buttonStyle(.plain)
            .enchronPressFeedback(.control)
            .accessibilityIdentifier("DesignPreview-PressFeedback-button-control")
            .accessibilityLabel("Preview control press feedback")

            Text("control · capsule")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var pressIconPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {} label: {
                Image(systemName: "play.fill")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.secondary)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                    .clipShape(Circle())
                    .glassBackgroundEffect(in: Circle())
                    .contentShape(.hoverEffect, Circle())
                    .hoverEffect(.automatic)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding((DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
            .enchronPressFeedback(.icon)
            .accessibilityIdentifier("DesignPreview-PressFeedback-button-icon")
            .accessibilityLabel("Preview icon press feedback")

            Text("icon · single target")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private func scaleText(_ spec: DesignTokens.PressFeedbackSpec) -> String {
        String(format: "%.3f", spec.pressedScale)
    }
}

// MARK: - Component standards

struct ComponentStandardsPreview: View {
    private var cardSpecs: [TokenSpec] {
        [
            .spec("paddingH", "16pt", "horizontal padding inside card text area") {
                tokenBarSwatch(DesignTokens.Card.paddingH, max: 48)
            },
            .spec("paddingV", "14pt", "vertical padding inside card text area") {
                tokenBarSwatch(DesignTokens.Card.paddingV, max: 48)
            },
            .spec("gridMin", "224pt", "adaptive grid minimum card width") {
                tokenBarSwatch(DesignTokens.Card.gridMin, max: 224)
            },
            .spec("thumbnailHeight", "140pt", "thumbnail height for grid cards") {
                tokenBarSwatch(DesignTokens.Card.thumbnailHeight, max: 224)
            },
            .spec("gridSpacing", "20pt", "grid inter-item spacing") {
                tokenBarSwatch(DesignTokens.Card.gridSpacing, max: 224)
            },
        ]
    }

    private var controlSpecs: [TokenSpec] {
        [
            .spec("width", "680pt", "matches Layout.playerControlsWidth") {
                tokenBarSwatch(DesignTokens.ControlBar.width, max: 680)
            },
            .spec("buttonSpacing", "24pt", "spacing between playback controls") {
                tokenBarSwatch(DesignTokens.ControlBar.buttonSpacing, max: 48)
            },
            .spec("paddingH", "32pt", "horizontal padding inside control capsule") {
                tokenBarSwatch(DesignTokens.ControlBar.paddingH, max: 48)
            },
            .spec("paddingV", "12pt", "vertical padding inside control capsule") {
                tokenBarSwatch(DesignTokens.ControlBar.paddingV, max: 48)
            },
            .spec("primaryFill", "white 0.72", "primary play button fill") {
                tokenColorSwatch(.white.opacity(0.72))
            },
            .spec("primarySymbol", "black 0.78", "primary play symbol color") {
                tokenColorSwatch(.black.opacity(0.78))
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Component Standards") {
            TokenSpecSection(
                title: "Card",
                namespace: "DesignTokens.Card.*",
                specs: cardSpecs
            ) {
                GridCard.video(title: "Interstellar", fileSize: "8.2 GB", duration: "2:49:00", badges: ["HDR10+"])
            }

            TokenSpecSection(
                title: "Control Bar",
                namespace: "DesignTokens.ControlBar.*",
                specs: controlSpecs
            ) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    dimensionBar("width", DesignTokens.ControlBar.width, maxWidth: 360)
                    FusedPlayerPanel()
                }
            }
        }
    }

    private func dimensionBar(_ title: String, _ width: CGFloat, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(title)  \(Int(width))pt")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: min(width, maxWidth), height: 28)
                .overlay(alignment: .trailing) {
                    Text("scaled")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, DesignTokens.Spacing.xs)
                }
        }
    }

    private func spacingBlock(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
            .fill(DesignTokens.Surface.elevated)
            .frame(width: DesignTokens.Interactive.regular, height: DesignTokens.Interactive.regular)
            .overlay {
                Text(title)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
    }
}
