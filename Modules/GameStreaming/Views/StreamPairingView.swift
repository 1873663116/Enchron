import DesignSystem
import SwiftUI

struct StreamPairingView: View {
    let hostID: HostID

    @Environment(StreamingModel.self) private var model
    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            header
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
    }

    private var host: HostSnapshot? {
        model.hosts.first { $0.id == hostID }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(host?.name ?? String(localized: "配对"))
                .font(DesignTokens.Typography.title)
                .lineLimit(1)
            if let address = host?.address.displayString {
                Text(address)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
            }
        }
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
            if challenge == nil || isFailed {
                Button {
                    Task { await beginPairing() }
                } label: {
                    Label("开始配对", systemImage: "link.badge.plus")
                }
                .disabled(isStarting)
                .accessibilityIdentifier("Stream-Pairing-start")
            } else {
                Button(role: .cancel) {
                    model.cancelPairing(hostID: hostID)
                } label: {
                    Label("取消", systemImage: "xmark")
                }
                .accessibilityIdentifier("Stream-Pairing-cancel")
            }

            if isStarting {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var failureLine: some View {
        if let failure = model.failure(for: hostID) {
            Text(LocalizedStringKey(failure.message))
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.SourceConnection.failureColor)
                .accessibilityIdentifier("Stream-Pairing-error")
                .accessibilityValue(failure.readableValue)
        }
    }

    private var challenge: PairingChallenge? {
        model.pairing(for: hostID)
    }

    private var pinText: String {
        challenge?.pin ?? "----"
    }

    private var pairingState: PairingState {
        challenge?.state ?? .unknown
    }

    private var statusSummary: String {
        switch pairingState {
        case .unknown: String(localized: "尚未开始")
        case .unpaired: String(localized: "等待主机确认")
        case .paired: String(localized: "已配对")
        case .failed(let message): String(localized: "配对失败（\(message)）")
        }
    }

    private var isFailed: Bool {
        if case .failed = pairingState {
            return true
        }
        return false
    }

    private func beginPairing() async {
        isStarting = true
        defer { isStarting = false }
        if challenge != nil {
            model.cancelPairing(hostID: hostID)
        }
        do {
            _ = try await model.beginPairing(hostID: hostID)
        } catch let failure as StreamFailure {
            model.recordFailure(failure, hostID: hostID)
        } catch {
            model.recordFailure(
                StreamFailure(
                    stage: .pairing,
                    kind: .unknown,
                    message: "配对无法开始",
                    recovery: .retry
                ),
                hostID: hostID
            )
        }
    }
}
