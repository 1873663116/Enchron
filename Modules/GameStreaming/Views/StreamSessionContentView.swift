import DesignSystem
import SwiftUI
import UIKit

public struct StreamSessionContentView: View {
    @Environment(StreamingModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    private var showsWeakNetworkHint: Bool {
        guard let session = model.session else { return false }
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
        .background(.regularMaterial, in: DesignTokens.ShapeToken.element)
        .padding(DesignTokens.Spacing.md)
        .allowsHitTesting(false)
        .accessibilityIdentifier("Stream-Session-stats")
    }

    public var body: some View {
        ZStack {
            StreamPointerInputLayer(
                videoAspectRatio: model.videoAspectRatio,
                onMove: { x, y in model.sendPointerMove(normalizedX: x, normalizedY: y) }
            )
            StreamTouchGestureSurface(
                configuration: StreamTouchGestureSurface.Configuration(
                    absoluteTouchMode: model.settings.absoluteTouchMode,
                    videoAspectRatio: model.videoAspectRatio,
                    currentZoom: CGFloat(model.streamZoom),
                    onMove: { point in
                        model.sendPointerMove(
                            normalizedX: Float(point.x),
                            normalizedY: Float(point.y)
                        )
                    },
                    onRelativeMove: { deltaX, deltaY in
                        model.sendRelativeMove(dx: Float(deltaX), dy: Float(deltaY))
                    },
                    onClick: { point in
                        model.releaseInputs(cause: "pointer-control")
                        model.sendGestureClick(
                            normalizedX: Float(point.x),
                            normalizedY: Float(point.y)
                        )
                    },
                    onRightButton: { down in
                        model.sendMouseButton(code: StreamMouseInput.rightButtonCode, down: down)
                    },
                    onScroll: { vertical, horizontal in
                        model.sendHighResScroll(vertical: vertical, horizontal: horizontal)
                    },
                    onMagnify: { scale in
                        model.setStreamZoom(Double(scale))
                    }
                )
            )
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
                    .background(.regularMaterial, in: Capsule())
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
                .background(.regularMaterial, in: DesignTokens.ShapeToken.element)
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

/// Moves the pointer with hover, which is what the absolute pointing path needs:
/// the wearer's gaze lands on a point and the host receives it without a click.
private struct StreamPointerInputLayer: View {
    let videoAspectRatio: CGFloat
    let onMove: (Float, Float) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let location) = phase {
                        if let normalized = StreamVideoGeometry.normalized(
                            location: location,
                            in: geometry.size,
                            videoAspectRatio: videoAspectRatio
                        ) {
                            onMove(Float(normalized.x), Float(normalized.y))
                        }
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
