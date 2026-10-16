import DesignSystem
import SwiftUI

struct StreamPairingView: View {
    let hostID: HostID

    @Environment(StreamingModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pairingRequested = false
    @State private var failureText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(hostName)
                .font(DesignTokens.Typography.title)
                .lineLimit(1)
            pinBlock
            statusLine
            controls
            failureLine
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-Pairing")
        .task { await beginIfNeeded() }
        .onChange(of: model.pairing?.state) { _, state in
            if state == .paired {
                dismiss()
            }
        }
    }

    private var hostName: String {
        model.hosts.first { $0.id == hostID }?.name ?? "配对"
    }

    private var pinBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("配对 PIN")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            Text(pinText)
                .font(DesignTokens.SymbolSize.hero)
                .monospacedDigit()
                .accessibilityIdentifier("Stream-Pairing-PIN")
                .accessibilityValue(pinText)
            Text("在主机端的配对页面输入该 PIN 并确认，例如 Sunshine 的 Web UI。")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.supportingText)
        }
    }

    private var statusLine: some View {
        Text("配对状态：\(statusSummary)")
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(DesignTokens.Surface.supportingText)
            .accessibilityIdentifier("Stream-Pairing-status")
            .accessibilityValue("pairing=\(pairingState.readableValue)")
    }

    private var controls: some View {
        HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
            Button(role: .cancel) {
                model.cancelPairing()
                dismiss()
            } label: {
                Label("取消", systemImage: "xmark")
            }
            .accessibilityIdentifier("Stream-Pairing-cancel")

            if isFailed {
                Button {
                    model.cancelPairing()
                    Task { await beginPairing() }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("Stream-Pairing-retry")
            }
        }
    }

    @ViewBuilder
    private var failureLine: some View {
        if let failureText {
            Text(failureText)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.SourceConnection.failureColor)
        }
    }

    private var pinText: String {
        model.pairing?.pin ?? "----"
    }

    private var pairingState: PairingState {
        model.pairing?.state ?? .unknown
    }

    private var statusSummary: String {
        switch pairingState {
        case .unknown: "尚未开始"
        case .unpaired: "等待主机确认"
        case .paired: "已配对"
        case .failed: "配对失败"
        }
    }

    private var isFailed: Bool {
        if case .failed = pairingState {
            return true
        }
        return failureText != nil
    }

    private func beginIfNeeded() async {
        guard pairingRequested == false else { return }
        pairingRequested = true
        if model.pairing?.state == .paired {
            model.clearPairing()
        }
        guard model.pairing == nil else { return }
        await beginPairing()
    }

    private func beginPairing() async {
        failureText = nil
        do {
            _ = try await model.beginPairing(hostID: hostID)
        } catch let failure as StreamFailure {
            failureText = failure.readableValue
        } catch {
            failureText = "配对无法开始"
        }
    }
}
