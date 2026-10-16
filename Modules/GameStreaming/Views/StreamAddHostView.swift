import DesignSystem
import SwiftUI

struct StreamAddHostView: View {
    private enum Mode {
        case chooser
        case discovery
        case manual
    }

    @Environment(StreamingModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .chooser
    @State private var addressText = ""
    @State private var nameText = ""
    @State private var isSubmitting = false
    @State private var failureText: String?
    @State private var failureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header
            entries
            switch mode {
            case .chooser:
                chooserHint
            case .discovery:
                discoverySection
            case .manual:
                manualSection
            }
            failureLine
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-AddHost")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            CircleIconButton.back(
                accessibilityLabel: "返回",
                action: { dismiss() },
                accessibilityIdentifier: "Stream-AddHost-back"
            )
            Text("添加主机")
                .font(DesignTokens.Typography.title)
            Spacer(minLength: 0)
        }
    }

    private var entries: some View {
        HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
            GlassCapsuleIconLabelButton(
                title: "发现",
                systemName: "dot.radiowaves.left.and.right",
                accessibilityLabel: "发现主机",
                action: { mode = .discovery },
                accessibilityIdentifier: "Stream-AddHost-discover-entry"
            )
            GlassCapsuleIconLabelButton(
                title: "手动添加",
                systemName: "keyboard",
                accessibilityLabel: "手动添加",
                action: { mode = .manual },
                accessibilityIdentifier: "Stream-AddHost-manual-entry"
            )
        }
    }

    private var chooserHint: some View {
        Text("主机与 Enchron 在同一网络时可自动发现；也可以直接输入主机地址。")
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("同一网络内的主机")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                if model.isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.discoveredHosts.enumerated()), id: \.offset) { index, host in
                    discoveryRow(host, index: index)
                }
            }
            .enchronListGroupSurface(cornerRadius: DesignTokens.Radius.element)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("Stream-Discovery-list")

            if model.discoveredHosts.isEmpty {
                Text("没有发现主机。确认主机与 Enchron 在同一网络，或改用手动添加。")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .accessibilityIdentifier("Stream-Discovery-empty")
                    .accessibilityValue("empty")
            }
        }
        .task { model.startDiscovery() }
        .onDisappear { model.stopDiscovery() }
    }

    private func discoveryRow(_ host: DiscoveredHost, index: Int) -> some View {
        ListGroupRowShell(
            index: index,
            count: model.discoveredHosts.count,
            cornerRadius: DesignTokens.Radius.element,
            accessibilityLabel: host.instanceName,
            accessibilityValue: "host=\(host.instanceName);address=\(host.address.displayString)",
            action: { add(host) }
        ) { _ in
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(DesignTokens.Surface.accessoryText)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(host.instanceName)
                        .font(DesignTokens.Typography.selectionHeader)
                    Text(host.address.displayString)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(minHeight: DesignTokens.Interactive.rowHeight)
        }
        .accessibilityIdentifier("Stream-Discovery-row-\(host.instanceName)")
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            labelledField("主机地址", accessibilityIdentifier: "Stream-ManualAddress-field") {
                TextField(
                    "主机地址",
                    text: $addressText,
                    prompt: Text("如 192.168.1.20 或 主机名")
                )
            }
            labelledField("显示名称", accessibilityIdentifier: "Stream-ManualName-field") {
                TextField("显示名称", text: $nameText, prompt: Text("可选"))
            }
            HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
                Button {
                    Task { await submit(address: addressText, name: nameText) }
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .disabled(isSubmitting || trimmedAddress.isEmpty)
                .accessibilityIdentifier("Stream-ManualAdd-submitButton")
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .enchronLiteralTextInput()
    }

    private func labelledField(
        _ label: String,
        accessibilityIdentifier: String,
        @ViewBuilder field: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            field()
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityLabel(label)
        }
    }

    @ViewBuilder
    private var failureLine: some View {
        if let failureText {
            Text(failureMessage ?? failureText)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.SourceConnection.failureColor)
                .accessibilityIdentifier("Stream-AddHost-error")
                .accessibilityValue(failureText)
        }
    }

    private var trimmedAddress: String {
        addressText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add(_ host: DiscoveredHost) {
        Task { await submit(address: host.address.displayString, name: host.instanceName) }
    }

    private func submit(address: String, name: String) async {
        isSubmitting = true
        failureText = nil
        failureMessage = nil
        defer { isSubmitting = false }
        do {
            let hostID = try await model.addHost(
                addressString: address,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
            )
            model.selectHost(hostID)
            dismiss()
        } catch let failure as StreamFailure {
            failureText = failure.readableValue
            failureMessage = failure.message
        } catch {
            failureText = String(describing: error)
            failureMessage = "添加主机失败"
        }
    }
}
