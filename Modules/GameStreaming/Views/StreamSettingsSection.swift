import CoreMedia
import DesignSystem
import SwiftUI
import VideoToolbox

public struct StreamSettingsSection: View {
    @Environment(StreamingModel.self) private var model

    private let av1DecodeAvailable: Bool
    @State private var isConfirmingCustomBitrate = false
    @State private var customBitrateText = ""

    public init() {
        av1DecodeAvailable = StreamCodecAvailability.av1DecodeSupported
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-resolutionGroup",
                items: resolutionItems
            )
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-bitrateGroup",
                items: bitrateItems
            )
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-timingGroup",
                items: timingItems
            )
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-qualityGroup",
                items: qualityItems
            )
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-inputGroup",
                items: inputItems
            )
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-hostGroup",
                items: hostItems
            )
            sessionConfigurationGroup
                .enchronDestructiveConfirmation(
                    "启用自定义码率？",
                    message: "超过档位上限的码率会让主机编码与头显解码更吃力，可能造成卡顿、掉帧与设备发热。只有在网络与设备都余量充足时才建议开启。",
                    confirmTitle: "启用",
                    isPresented: $isConfirmingCustomBitrate
                ) {
                    applyCustomBitrateEnabled(true)
                }
        }
    }

    private var resolutionItems: [SettingListGroup.Item] {
        var item = SettingListGroup.Item(
            id: "Streaming-resolution",
            title: "分辨率",
            systemName: "rectangle.on.rectangle",
            accessory: .menu(title: resolutionMenuTitle, options: resolutionOptions)
        )
        if model.settings.resolution == .custom {
            item.embeddedControl = .numberFields(fields: [
                SettingListGroup.NumberField(
                    id: "Streaming-customWidth",
                    title: "宽度",
                    text: customWidthText,
                    suffix: nil,
                    message: customWidthMessage
                ),
                SettingListGroup.NumberField(
                    id: "Streaming-customHeight",
                    title: "高度",
                    text: customHeightText,
                    suffix: nil,
                    message: customHeightMessage
                )
            ])
        }
        return [item]
    }

    private var bitrateItems: [SettingListGroup.Item] {
        var items: [SettingListGroup.Item] = [
            SettingListGroup.Item(
                id: "Streaming-bitrate",
                title: "码率",
                systemName: "gauge.with.dots.needle.bottom.50percent",
                accessory: .value(bitrateLabel),
                embeddedControl: .detentedSlider(
                    selectedIndex: bitrateLadderIndex,
                    detentCount: StreamOptions.bitrateLadderMbps.count,
                    valueText: bitrateLabel,
                    accessibilityLabel: "码率",
                    isEnabled: model.settings.customBitrateEnabled == false
                )
            ),
            SettingListGroup.Item(
                id: "Streaming-customBitrate",
                title: "自定义码率",
                systemName: "slider.horizontal.3",
                supportingText: "高码率会让主机编码与头显解码更吃力，可能造成卡顿与发热。",
                supportingTextLineLimit: nil,
                accessory: .boundToggle(
                    isOn: customBitrateBinding,
                    isEnabled: true,
                    marker: nil
                ),
                embeddedControl: model.settings.customBitrateEnabled
                    ? .numberFields(fields: [
                        SettingListGroup.NumberField(
                            id: "Streaming-customBitrateInput",
                            title: "上限",
                            text: customBitrateTextBinding,
                            suffix: "Mbps",
                            message: customBitrateMessage
                        )
                    ])
                    : nil
            )
        ]
        return items
    }

    private var timingItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "Streaming-frameRate",
                title: "帧率",
                systemName: "speedometer",
                accessory: .menu(title: frameRateLabel, options: frameRateOptions)
            ),
            SettingListGroup.Item(
                id: "Streaming-frameBuffer",
                title: "帧调度",
                systemName: "metronome",
                supportingText: "按显示刷新节奏安排帧呈现。",
                accessory: .menu(title: framePacingLabel, options: framePacingOptions)
            )
        ]
    }

    private var qualityItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "Streaming-codec",
                title: "编码格式",
                systemName: "film",
                supportingText: codecSupportingText,
                accessory: .menu(title: model.settings.codec.label, options: codecOptions)
            ),
            SettingListGroup.Item(
                id: "Streaming-hdr",
                title: "HDR (Beta)",
                systemName: "sun.max",
                supportingText: hdrExplanation,
                supportingTextLineLimit: nil,
                accessory: .boundToggle(
                    isOn: hdrBinding,
                    isEnabled: model.settings.codec != .h264,
                    marker: nil
                )
            )
        ]
    }

    private var inputItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "Streaming-swapABXY",
                title: "交换 ABXY",
                systemName: "gamecontroller",
                supportingText: "适配任天堂式按键布局：A 与 B、X 与 Y 互换。",
                accessory: .boundToggle(isOn: swapABXYBinding, isEnabled: true, marker: nil)
            ),
            SettingListGroup.Item(
                id: "Streaming-bluetoothMouse",
                title: "蓝牙鼠标",
                systemName: "computermouse",
                supportingText: "外接鼠标直接控制主机指针：转发移动、按键与滚轮。",
                accessory: .boundToggle(isOn: bluetoothMouseBinding, isEnabled: true, marker: nil)
            )
        ]
    }

    private var hostItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "Streaming-audioOnPC",
                title: "PC 端播放音频",
                systemName: "hifispeaker",
                supportingText: "声音留在主机扬声器，不串流到本机。",
                accessory: .boundToggle(isOn: audioOnPCBinding, isEnabled: true, marker: nil)
            ),
            SettingListGroup.Item(
                id: "Streaming-optimizeSettings",
                title: "优化游戏设置",
                systemName: "wand.and.stars",
                supportingText: "请求主机为串流调整游戏内设置；仅 GeForce Experience 主机响应。",
                supportingTextLineLimit: nil,
                accessory: .boundToggle(isOn: optimizeGameSettingsBinding, isEnabled: true, marker: nil)
            )
        ]
    }

    private var swapABXYBinding: Binding<Bool> {
        Binding(
            get: { model.settings.swapABXYButtons },
            set: { value in model.updateSettings { $0.swapABXYButtons = value } }
        )
    }

    private var bluetoothMouseBinding: Binding<Bool> {
        Binding(
            get: { model.settings.bluetoothMouseEnabled },
            set: { value in model.updateSettings { $0.bluetoothMouseEnabled = value } }
        )
    }

    private var audioOnPCBinding: Binding<Bool> {
        Binding(
            get: { model.settings.playAudioOnPC },
            set: { value in model.updateSettings { $0.playAudioOnPC = value } }
        )
    }

    private var optimizeGameSettingsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.optimizeGameSettings },
            set: { value in model.updateSettings { $0.optimizeGameSettings = value } }
        )
    }

    private var customWidthText: Binding<String> {
        dimensionText(
            get: { model.settings.customWidth },
            set: { applyCustomWidth($0) }
        )
    }

    private var customHeightText: Binding<String> {
        dimensionText(
            get: { model.settings.customHeight },
            set: { applyCustomHeight($0) }
        )
    }

    private func dimensionText(
        get: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<String> {
        Binding(
            get: { "\(get())" },
            set: { text in
                guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else {
                    return
                }
                set(value)
            }
        )
    }

    private func applyCustomWidth(_ value: Int) {
        guard value > 0 else { return }
        applyBitrateFollowing { $0.customWidth = value }
    }

    private func applyCustomHeight(_ value: Int) {
        guard value > 0 else { return }
        applyBitrateFollowing { $0.customHeight = value }
    }

    private var customWidthMessage: String? {
        guard model.settings.customWidth > 0 else { return "请输入正整数" }
        guard StreamResolution.customWidthRange.contains(model.settings.customWidth) else {
            return "宽度需在 \(StreamResolution.customWidthRange.lowerBound) 到 \(StreamResolution.customWidthRange.upperBound) 之间"
        }
        return dimensionPairMessage
    }

    private var customHeightMessage: String? {
        guard model.settings.customHeight > 0 else { return "请输入正整数" }
        guard StreamResolution.customHeightRange.contains(model.settings.customHeight) else {
            return "高度需在 \(StreamResolution.customHeightRange.lowerBound) 到 \(StreamResolution.customHeightRange.upperBound) 之间"
        }
        return dimensionPairMessage
    }

    private var dimensionPairMessage: String? {
        guard StreamResolution.isCustomDimensionsValid(
            width: model.settings.customWidth,
            height: model.settings.customHeight
        ) else {
            return "宽高相乘不能超过 7680 × 4320"
        }
        return nil
    }

    private var customBitrateTextBinding: Binding<String> {
        Binding(
            get: { customBitrateText },
            set: { text in
                customBitrateText = text
                guard let kbps = parsedCustomBitrateKbps else { return }
                model.updateSettings { $0.bitrateKbps = kbps }
            }
        )
    }

    private var parsedCustomBitrateKbps: Int? {
        guard let megabits = Int(customBitrateText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let kbps = megabits * 1000
        guard StreamOptions.customBitrateKbpsRange.contains(kbps) else {
            return nil
        }
        return kbps
    }

    private var customBitrateMessage: String? {
        guard customBitrateText.isEmpty == false else { return "请输入数值" }
        guard parsedCustomBitrateKbps == nil else { return nil }
        let low = StreamOptions.customBitrateKbpsRange.lowerBound / 1000
        let high = StreamOptions.customBitrateKbpsRange.upperBound / 1000
        return "请输入 \(low) 到 \(high) 之间的整数"
    }

    private var customBitrateBinding: Binding<Bool> {
        Binding(
            get: { model.settings.customBitrateEnabled },
            set: { isOn in
                if isOn {
                    customBitrateText = "\(model.settings.bitrateKbps / 1000)"
                    isConfirmingCustomBitrate = true
                } else {
                    applyCustomBitrateEnabled(false)
                }
            }
        )
    }

    private func applyCustomBitrateEnabled(_ isOn: Bool) {
        model.updateSettings { $0.customBitrateEnabled = isOn }
        if isOn {
            customBitrateText = "\(model.settings.bitrateKbps / 1000)"
        }
    }

    private var resolutionMenuTitle: String {
        guard model.settings.resolution == .custom else {
            return model.settings.resolution.label
        }
        return "自定义　\(model.settings.customWidth) × \(model.settings.customHeight)"
    }

    private var resolutionOptions: [SettingListGroup.MenuOption] {
        StreamResolution.allCases.map { resolution in
            SettingListGroup.MenuOption(resolution.label, id: resolution.rawValue) {
                applyBitrateFollowing { $0.resolution = resolution }
            }
        }
    }

    private var frameRateOptions: [SettingListGroup.MenuOption] {
        StreamOptions.defaultFrameRates.map { frameRate in
            SettingListGroup.MenuOption("\(frameRate) fps", id: "\(frameRate)") {
                applyBitrateFollowing { $0.frameRate = frameRate }
            }
        }
    }

    private var bitrateLadderIndex: Binding<Int> {
        Binding(
            get: {
                let current = StreamOptions.nearestLadderMbps(model.settings.bitrateKbps)
                return StreamOptions.bitrateLadderMbps.firstIndex(of: current) ?? 0
            },
            set: { index in
                let clamped = min(max(index, 0), StreamOptions.bitrateLadderMbps.count - 1)
                model.updateSettings {
                    $0.bitrateKbps = StreamOptions.bitrateLadderMbps[clamped] * 1000
                }
            }
        )
    }

    private var codecOptions: [SettingListGroup.MenuOption] {
        StreamCodecPreference.allCases
            .filter { $0 != .av1 || av1DecodeAvailable }
            .map { codec in
                SettingListGroup.MenuOption(codec.label, id: codec.rawValue) {
                    model.updateSettings { $0.codec = codec }
                }
            }
    }

    private var codecSupportingText: String? {
        nil
    }

    private var hdrExplanation: String {
        "接收 HDR 视频并交由系统以 HDR 呈现。需要主机启用 HDR，并提供 HDR 视频信号。不支持 H.264 编码。"
    }

    private var hdrBinding: Binding<Bool> {
        Binding(
            get: { model.settings.hdrEnabled },
            set: { value in model.updateSettings { $0.hdrEnabled = value } }
        )
    }

    private var framePacingLabel: String {
        model.settings.frameBuffer ? "平滑优先" : "延迟优先"
    }

    private var framePacingOptions: [SettingListGroup.MenuOption] {
        [
            SettingListGroup.MenuOption("平滑优先", id: "smooth") {
                model.updateSettings { $0.frameBuffer = true }
            },
            SettingListGroup.MenuOption("延迟优先", id: "latency") {
                model.updateSettings { $0.frameBuffer = false }
            }
        ]
    }

    private func applyBitrateFollowing(_ mutate: (inout StreamOptions) -> Void) {
        model.updateSettings { options in
            mutate(&options)
            guard options.customBitrateEnabled == false, options.resolution != .custom else {
                return
            }
            options.bitrateKbps = options.suggestedBitrateKbps()
        }
    }

    private var frameRateLabel: String {
        "\(model.settings.frameRate) fps"
    }

    private var bitrateLabel: String {
        "\(model.settings.bitrateKbps / 1000) Mbps"
    }

    private var requestedValue: String {
        model.settings.readableValue
    }

    private var negotiatedValue: String {
        model.session?.negotiated?.readableValue ?? "unavailable"
    }

    private var sessionConfigurationGroup: some View {
        VStack(spacing: 0) {
            ListGroupRowShell(
                index: 0,
                count: 2,
                cornerRadius: DesignTokens.Radius.element,
                isInteractive: false,
                accessibilityLabel: "当前会话实际协商配置",
                accessibilityValue: negotiatedValue
            ) { _ in
                configurationRow(title: "当前会话实际协商配置", value: negotiatedValue)
            }
            .accessibilityIdentifier("Settings-Streaming-negotiated")

            ListGroupRowShell(
                index: 1,
                count: 2,
                cornerRadius: DesignTokens.Radius.element,
                isInteractive: false,
                accessibilityLabel: "下一次连接使用的配置",
                accessibilityValue: requestedValue
            ) { _ in
                configurationRow(title: "下一次连接使用的配置", value: requestedValue)
            }
            .accessibilityIdentifier("Settings-Streaming-requested")
        }
        .enchronListGroupSurface(cornerRadius: DesignTokens.Radius.element)
    }

    private func configurationRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.lg) {
            Text(title)
                .font(DesignTokens.Typography.selectionHeader)
                .foregroundStyle(DesignTokens.Surface.selectionHeaderText)
            Spacer(minLength: DesignTokens.Spacing.lg)
            Text(value)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
    }
}
