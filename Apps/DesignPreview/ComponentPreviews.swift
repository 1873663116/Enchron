import DesignSystem
import MediaLibrary
import PlaybackFeature
import PlaybackPresentation
import SwiftUI


struct PlaybackControlsPreview: View {
    @State private var isPlaying = true
    @State private var progress: CGFloat = 0.45
    @State private var screenScale = 1.0
    @State private var screenDistance = PlaybackDockedPlacement.defaultDistance
    @State private var screenElevation = PlaybackDockedPlacement.defaultElevationDegrees
    @State private var projection: PlaybackModel.ProjectionType = .equirectangular180
    @State private var stereoLayout: PlaybackModel.StereoLayout = .sideBySide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                Text("PLAYBACK CONTROLS BY PRESENTATION")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary)

                playbackPresentationSection(
                    title: "Window",
                    supporting: "Window Playback Ornament keeps its own compact composition",
                    presentation: .window
                )

                playbackPresentationSection(
                    title: "Docked",
                    supporting: "Settings opens placement controls · Collapse returns to Window",
                    presentation: .docked
                )

                playbackPresentationSection(
                    title: "Panorama",
                    supporting: "Settings opens media format controls · Collapse Vertically returns to Window",
                    presentation: .panorama
                )
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Playback Controls")
    }

    private func playbackPresentationSection(
        title: String,
        supporting: String,
        presentation: PlaybackPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(DesignTokens.Typography.title)
                Text(supporting)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }

            previewState("Collapsed", presentation: presentation, expansion: .collapsed)
            previewState("Timeline Expanded", presentation: presentation, expansion: .timeline)
            if presentation != .window {
                previewState("Settings Expanded", presentation: presentation, expansion: .settings)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignPreview-PlaybackControls-\(presentation.rawValue)")
    }

    @ViewBuilder
    private func previewState(
        _ title: String,
        presentation: PlaybackPresentation,
        expansion: PlaybackPanelInitialExpansion
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)

            if presentation == .window {
                WindowPlaybackControls(
                    live: live(presentation: presentation),
                    initialExpansion: expansion
                )
            } else {
                PlayerControlDock(
                    live: live(presentation: presentation),
                    initialExpansion: expansion
                )
            }
        }
    }

    private func live(presentation: PlaybackPresentation) -> FusedPlayerPanelLive {
        FusedPlayerPanelLive(
            presentation: presentation,
            mediaName: "Dune.Part.Two.2024",
            mediaProfile: mediaProfile(for: presentation),
            canDock: true,
            canEnterPanorama: true,
            screenScale: screenScale,
            recommendedScreenScale: 1.0,
            screenDistance: screenDistance,
            screenElevationDegrees: screenElevation,
            projection: presentation == .panorama ? projection : .flat,
            stereoLayout: presentation == .panorama ? stereoLayout : .mono,
            canUseFisheye: true,
            isPlaying: isPlaying,
            showsReplay: false,
            canSkipForward: true,
            canStepForward: true,
            progress: progress,
            elapsedLabel: PlaybackTimeFormatter.clock(Double(progress) * 855),
            durationLabel: "14:15",
            duration: 855,
            framesPerSecond: 23.976,
            onPlayPause: { isPlaying.toggle() },
            onSkipBackward: { progress = max(0, progress - CGFloat(15.0 / 855.0)) },
            onSkipForward: { progress = min(1, progress + CGFloat(15.0 / 855.0)) },
            onSeek: { progress = $0 },
            onPrecisionSeek: { progress = $0 },
            onFrameStep: { direction in
                progress = min(max(progress + CGFloat(direction) / CGFloat(855 * 24), 0), 1)
            },
            onEnterPanorama: {},
            onEnterImmersive: {},
            onExitSpatial: {},
            onExitPlayback: {},
            onSetScreenScale: { screenScale = $0 },
            onSetScreenDistance: { screenDistance = $0 },
            onSetScreenElevation: { screenElevation = $0 },
            onResetDockedPlacement: {
                screenScale = 1.0
                screenDistance = PlaybackDockedPlacement.defaultDistance
                screenElevation = PlaybackDockedPlacement.defaultElevationDegrees
            },
            onApplyFormat: { projection = $0; stereoLayout = $1 },
            onResetFormat: {
                projection = .flat
                stereoLayout = .mono
            },
            subtitleItems: menuItems(["Off", "English CC"], selected: "Off"),
            audioItems: menuItems(["English 5.1", "Japanese 2.0"], selected: "English 5.1"),
            speedItems: menuItems(["0.5×", "1×", "1.5×", "2×"], selected: "1×"),
            episodeItems: menuItems(["Episode 1", "Episode 2"], selected: "Episode 1")
        )
    }

    private func mediaProfile(
        for presentation: PlaybackPresentation
    ) -> PlaybackModel.MediaProfile {
        let isPanorama = presentation == .panorama
        return PlaybackModel.MediaProfile(
            projectionType: isPanorama ? projection : .flat,
            stereoLayout: isPanorama ? stereoLayout : .mono,
            hdrType: .hdr10,
            resolution: .init(
                width: 3840,
                height: isPanorama ? 1920 : 2160
            ),
            frameRate: 23.976,
            videoCodec: "hevc",
            durationSeconds: 855
        )
    }

    private func menuItems(_ titles: [String], selected: String) -> [DeckMenuItem] {
        titles.map { title in
            DeckMenuItem(
                id: title,
                title: title,
                isSelected: title == selected,
                action: {}
            )
        }
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

// 三种滑块的真相展示面:CenterSlider(居中档位)、RangeSlider(连续数值域)、
// DetentedRangeSlider(leading-origin 档位,与 Docked Placement 同一套几何)。
struct SliderPreview: View {
    @State private var exposure = 0
    @State private var fineAdjust = -2
    @State private var peakPercentile = 99.9
    @State private var targetPeak = 406.0
    @State private var saturation = 9.0
    @State private var screenScale = 1.0
    @State private var distance = PlaybackDockedPlacement.defaultDistance
    @State private var elevation = PlaybackDockedPlacement.defaultElevationDegrees

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                centerSliderSection
                rangeSliderSection
                detentedRangeSliderSection
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

    private var detentedRangeSliderSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Detented Range Slider")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(.primary)
            Text("leading-origin、共享 \(PlaybackDockedPlacement.placementDetentCount) 档、Binding<Double>;与 Docked Placement 三行同一套点列几何。")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)

            detentedRow(
                "Screen Size",
                value: $screenScale,
                range: PlaybackScreenSize.scaleRange,
                step: PlaybackScreenSize.scaleStep,
                label: { "\(Int(($0 * 100).rounded()))%" }
            )
            detentedRow(
                "Distance",
                value: $distance,
                range: PlaybackDockedPlacement.distanceRange,
                step: PlaybackDockedPlacement.distanceStep,
                label: { String(format: "%.1f m", $0) }
            )
            detentedRow(
                "Elevation",
                value: $elevation,
                range: PlaybackDockedPlacement.elevationRange,
                step: PlaybackDockedPlacement.elevationStep,
                label: { "\(Int($0.rounded()))°" }
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

    private func detentedRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        label: (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                Text(label(value.wrappedValue))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            DetentedRangeSlider(
                value: value,
                range: range,
                step: step,
                accessibilityLabel: title,
                accessibilityValue: label(value.wrappedValue),
                accessibilityIdentifier: "DesignPreview-DetentedRangeSlider-\(title)"
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
