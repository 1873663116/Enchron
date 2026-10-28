import DesignSystem
import SwiftUI

public struct StreamSessionContentView: View {
    @Environment(StreamingModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    private var showsWeakNetworkHint: Bool {
        guard let session = model.session else { return false }
#if DEBUG
        if let injected = model.debugConnectionQuality {
            return session.state == .streaming && injected == 1
        }
#endif
        return session.state == .streaming && session.diagnostics.connectionQuality == 1
    }

    private var interruptedFailure: StreamFailure? {
        guard let session = model.session, case .interrupted = session.state else { return nil }
        return session.failure
    }

    private var showsPerformanceOverlay: Bool {
        guard model.settings.showPerformanceOverlay, let session = model.session else { return false }
        return session.state == .streaming
    }

    /// The numbers the session already tracks: what was negotiated, how fast it
    /// arrives, and how far behind the network is. Nothing here is sampled
    /// separately, so the overlay costs no extra work.
    private func performanceOverlay(_ session: SessionSnapshot) -> some View {
        let negotiated = session.negotiated
        let diagnostics = session.diagnostics
        var lines: [String] = []
        if let negotiated {
            lines.append("\(negotiated.width)×\(negotiated.height)@\(negotiated.frameRate)")
            lines.append("\(negotiated.codec.displayName) · \(negotiated.audioChannels) 声道")
        } else {
            lines.append("协商中")
        }
        var stats: [String] = []
        if let fps = diagnostics.presentedFramesPerSecond {
            stats.append("\(fps) fps")
        }
        if let bitrate = diagnostics.measuredBitrateKbps {
            stats.append("\(bitrate) kbps")
        }
        if let rtt = diagnostics.estimatedRttMs {
            stats.append("RTT \(rtt) ms")
        }
        if diagnostics.networkDroppedFrames > 0 {
            stats.append("丢帧 \(diagnostics.networkDroppedFrames)")
        }
        if !stats.isEmpty {
            lines.append(stats.joined(separator: " · "))
        }
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(DesignTokens.Typography.monospacedDetail)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(DesignTokens.Surface.hudBackdrop, in: DesignTokens.ShapeToken.element)
        .foregroundStyle(.white)
        .padding(DesignTokens.Spacing.md)
        .allowsHitTesting(false)
        .accessibilityIdentifier("Stream-Session-stats")
    }

    public var body: some View {
        ZStack {
            StreamFocusedInputCapture(
                onKey: { usage, down, flags in
                    model.sendKey(
                        hidUsage: UInt32(usage.rawValue),
                        down: down,
                        modifierFlags: UInt32(flags.rawValue)
                    )
                }
            )
        }
        .overlay(alignment: .bottomTrailing) {
            Text(model.session?.state.readableValue ?? "unavailable")
                .font(DesignTokens.Typography.monospacedDetail)
                .foregroundStyle(.clear)
                .accessibilityIdentifier("Stream-Session-snapshot")
                .accessibilityValue(model.session?.readableValue ?? "unavailable")
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if showsPerformanceOverlay, let session = model.session {
                performanceOverlay(session)
            }
        }
        .overlay(alignment: .top) {
            if showsWeakNetworkHint {
                Text(verbatim: "网络不稳：画面与操作可能延迟")
                    .font(DesignTokens.Typography.monospacedDetail)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(DesignTokens.Surface.hudBackdrop, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, DesignTokens.Spacing.md)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("Stream-Session-networkHint")
            }
        }
        .overlay {
            if let failure = interruptedFailure {
                VStack(spacing: DesignTokens.Spacing.sm) {
                    Text(LocalizedStringKey(failure.message))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if failure.recovery == .reconnect || failure.recovery == .retry {
                        Button {
                            Task { try? await model.reconnect() }
                        } label: {
                            Text(verbatim: "重新连接")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
                .background(.orange, in: DesignTokens.ShapeToken.element)
                .padding(DesignTokens.Spacing.xxl)
                .accessibilityIdentifier("Stream-Session-failure")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            StreamSessionProbes.record(
                "window scene phase=\(String(describing: phase))"
                    + " session=\(model.session?.id.rawValue ?? "none")",
                retention: .evidence
            )
            if phase != .active {
                model.releaseInputs(cause: "background")
            }
        }
        .onDisappear {
            StreamSessionProbes.record(
                "stream content disappeared session=\(model.session?.id.rawValue ?? "none")",
                retention: .evidence
            )
            model.releaseInputs(cause: "disconnect")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-Session-content")
    }
}
