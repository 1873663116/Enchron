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
                accessibilityIdentifier: "Settings-Streaming-group",
                items: settingItems
            )
            if model.settings.customBitrateEnabled {
                customBitrateInputRow
                    .enchronListGroupSurface(cornerRadius: DesignTokens.Radius.element)
            }
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

    private var settingItems: [SettingListGroup.Item] {
        var items: [SettingListGroup.Item] = [
            SettingListGroup.Item(
                id: "Streaming-resolution",
                title: "分辨率",
                systemName: "rectangle.on.rectangle",
                accessory: .menu(title: resolutionMenuTitle, options: resolutionOptions)
            )
        ]
        if model.settings.resolution == .custom {
            items.append(
                SettingListGroup.Item(
                    id: "Streaming-customResolution",
                    title: "自定义尺寸",
                    systemName: "aspectratio",
                    accessory: .value("\(model.settings.customWidth) × \(model.settings.customHeight)"),
                    embeddedControl: .dimensionSteppers(
                        width: customWidthBinding,
                        height: customHeightBinding,
                        widthRange: StreamResolution.customWidthRange,
                        heightRange: StreamResolution.customHeightRange,
                        step: 16
                    )
                )
            )
        }
        items.append(contentsOf: [
            SettingListGroup.Item(
                id: "Streaming-frameRate",
                title: "帧率",
                systemName: "speedometer",
                accessory: .menu(title: frameRateLabel, options: frameRateOptions)
            ),
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
                )
            ),
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
            ),
            SettingListGroup.Item(
                id: "Streaming-framePacing",
                title: "帧调度",
                systemName: "metronome",
                supportingText: "按显示刷新节奏安排帧呈现。",
                accessory: .menu(title: framePacingLabel, options: framePacingOptions)
            )
        ])
        return items
    }

    private var customWidthBinding: Binding<Int> {
        Binding(
            get: { model.settings.customWidth },
            set: { value in
                applyBitrateFollowing { $0.customWidth = value }
            }
        )
    }

    private var customHeightBinding: Binding<Int> {
        Binding(
            get: { model.settings.customHeight },
            set: { value in
                applyBitrateFollowing { $0.customHeight = value }
            }
        )
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

    private func seedCustomBitrateText() {
        guard customBitrateText.isEmpty else { return }
        customBitrateText = "\(model.settings.bitrateKbps / 1000)"
    }

    private func applyCustomBitrateEnabled(_ isOn: Bool) {
        model.updateSettings { $0.customBitrateEnabled = isOn }
        if isOn {
            customBitrateText = "\(model.settings.bitrateKbps / 1000)"
        }
    }

    private var customBitrateKbps: Int? {
        guard let megabits = Int(customBitrateText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let kbps = megabits * 1000
        guard StreamOptions.customBitrateKbpsRange.contains(kbps) else {
            return nil
        }
        return kbps
    }

    private var customBitrateInputRow: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("码率上限")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            TextField("300", text: $customBitrateText)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("Settings-Streaming-customBitrateInput")
                .frame(width: DesignTokens.Layout.settingsValueColumnWidth)
                .onChange(of: customBitrateText) { _, _ in
                    guard let kbps = customBitrateKbps else { return }
                    model.updateSettings { $0.bitrateKbps = kbps }
                }
            Text("Mbps")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            Spacer(minLength: 0)
            if customBitrateKbps == nil, customBitrateText.isEmpty == false {
                Text("请输入 1 到 500 之间的整数")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.destructiveAction)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.md)
        .onAppear { seedCustomBitrateText() }
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
        av1DecodeAvailable ? nil : "本机不支持 AV1 硬件解码，AV1 不可选。"
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
        model.settings.framePacing ? "最平滑" : "最低延迟"
    }

    private var framePacingOptions: [SettingListGroup.MenuOption] {
        [
            SettingListGroup.MenuOption("最平滑", id: "smooth") { applyFramePacing(true) },
            SettingListGroup.MenuOption("最低延迟", id: "latency") { applyFramePacing(false) }
        ]
    }

    private func applyFramePacing(_ smooth: Bool) {
        model.updateSettings { $0.framePacing = smooth }
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
