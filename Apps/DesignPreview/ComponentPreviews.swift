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
            onChooseSubtitleFile: {},
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
            Text("leading-origin、按各产品量纲使用独立档位、Binding<Double>；与 Docked Placement 三行使用同一套滑杆实现。")
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

struct ConnectionFormFixture: View {
    let kind: SourceConnectionKind
    var onDismiss: () -> Void = {}

    @State private var name = ""
    @State private var address = ConnectionFormFixture.correctAddress
    @State private var share = "Videos"
    @State private var username = ConnectionFormFixture.correctUsername
    @State private var password = ConnectionFormFixture.correctPassword
    @State private var connectsAsGuest = false

    private static let correctAddress = "192.168.1.1"
    private static let correctUsername = "123"
    private static let correctPassword = "123"
    private let connectWaitDuration: Duration = .seconds(3)

    var body: some View {
        ConnectionFormPanel(
            kind: kind,
            name: $name,
            address: $address,
            share: $share,
            username: $username,
            password: $password,
            connectsAsGuest: $connectsAsGuest,
            accessibilityIdentifierPrefix: "DesignPreview-connection-\(kind.rawValue)",
            onConnect: mockConnect,
            onCancel: onDismiss,
            onConnected: onDismiss
        )
    }

    private func mockConnect(
        _ request: SourceConnectionRequest
    ) async -> SourceConnectionOutcome {
        do {
            try await Task.sleep(for: connectWaitDuration)
        } catch {
            return .failed(message: "Connection cancelled.")
        }

        guard request.address == Self.correctAddress else {
            return .timedOut(message: "Connection timed out. Check the address and network.")
        }
        guard request.connectsAsGuest
                || (request.username == Self.correctUsername
                    && request.password == Self.correctPassword)
        else {
            return .failed(message: "Authentication failed. Check the username and password.")
        }
        return .connected
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
                    panelColumn(kind: .webDAV, presented: $webdavPresented)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Connection Form")
    }

    private func panelColumn(
        kind: SourceConnectionKind,
        presented: Binding<Bool>
    ) -> some View {
        Group {
            if presented.wrappedValue {
                ConnectionFormFixture(
                    kind: kind,
                    onDismiss: { presented.wrappedValue = false }
                )
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
        .frame(width: DesignTokens.SourceConnection.panelWidth, alignment: .top)
        .animation(DesignTokens.AnimationToken.panelSpring, value: presented.wrappedValue)
    }
}

// MARK: - Token pages
