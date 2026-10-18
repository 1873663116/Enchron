import CoreMedia
import DesignSystem
import SwiftUI
import VideoToolbox

public struct StreamSettingsSection: View {
    @Environment(StreamingModel.self) private var model

    private let av1DecodeAvailable: Bool

    public init() {
        av1DecodeAvailable = StreamCodecAvailability.av1DecodeSupported
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            SettingListGroup(
                accessibilityIdentifier: "Settings-Streaming-group",
                items: settingItems
            )
            sessionConfigurationGroup
        }
    }

    private var settingItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "Streaming-resolution",
                title: "分辨率",
                systemName: "rectangle.on.rectangle",
                accessory: .menu(title: model.settings.resolution.label, options: resolutionOptions)
            ),
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
                accessory: .menu(title: bitrateLabel, options: bitrateOptions)
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
                title: "HDR",
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
                accessory: .boundToggle(
                    isOn: framePacingBinding,
                    isEnabled: true,
                    marker: nil
                )
            )
        ]
    }

    private var resolutionOptions: [SettingListGroup.MenuOption] {
        StreamResolution.allCases.map { resolution in
            SettingListGroup.MenuOption(resolution.label, id: resolution.rawValue) {
                model.updateSettings { $0.resolution = resolution }
            }
        }
    }

    private var frameRateOptions: [SettingListGroup.MenuOption] {
        StreamOptions.defaultFrameRates.map { frameRate in
            SettingListGroup.MenuOption("\(frameRate) fps", id: "\(frameRate)") {
                model.updateSettings { $0.frameRate = frameRate }
            }
        }
    }

    private var bitrateOptions: [SettingListGroup.MenuOption] {
        stride(
            from: StreamOptions.bitrateRangeMbps.lowerBound,
            through: StreamOptions.bitrateRangeMbps.upperBound,
            by: 10
        ).map { megabits in
            SettingListGroup.MenuOption("\(megabits) Mbps", id: "\(megabits)") {
                model.updateSettings { $0.bitrateKbps = megabits * 1000 }
            }
        }
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

    private var framePacingBinding: Binding<Bool> {
        Binding(
            get: { model.settings.framePacing },
            set: { value in model.updateSettings { $0.framePacing = value } }
        )
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
