import DesignSystem
import Playback
import SwiftUI
import UIKit

public struct StreamWindowView: View {
    @Environment(StreamingModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    @State private var degradeExplanationVisible = false

    public init() {}

    public var body: some View {
        WindowPlaybackRootView(
            geometryPolicy: .aspectLocked(WindowPlaybackLayout(aspectRatio: videoAspectRatio)),
            showsWindowChrome: true,
            videoContent: {
                ZStack {
                    Color.black
                    if let binding = model.renderBinding {
                        StreamVideoSurface(renderer: binding.videoRenderer)
                            .id(binding.version)
                    }
                    StreamPointerInputLayer(
                        videoAspectRatio: videoAspectRatio,
                        onMove: { x, y in model.sendPointerMove(normalizedX: x, normalizedY: y) },
                        onClick: { position in
                            model.releaseInputs(cause: "pointer-control")
                            model.sendPointerMove(
                                normalizedX: Float(position.x),
                                normalizedY: Float(position.y)
                            )
                            model.sendMouseButton(code: 1, down: true)
                            model.sendMouseButton(code: 1, down: false)
                        }
                    )
                    StreamKeyboardCapture(
                        onKey: { usage, down, flags in
                            model.sendKey(hidUsage: UInt32(usage.rawValue), down: down, modifierFlags: UInt32(flags.rawValue))
                        },
                        onFocusChange: { focused in
                            if !focused {
                                model.releaseInputs(cause: "focus-lost")
                            }
                        }
                    )
                }
            },
            topChrome: {
                StreamWindowChrome(
                    snapshot: model.session,
                    onBack: {
                        model.releaseInputs(cause: "disconnect")
                        model.disconnect()
                        dismissWindow(id: "streaming")
                    },
                    onDock: {
                        model.releaseInputs(cause: "control-hit")
                    },
                    onDegrade: {
                        model.releaseInputs(cause: "control-hit")
                        degradeExplanationVisible = true
                    }
                )
            }
        )
        .sheet(isPresented: $degradeExplanationVisible) {
            StreamDegradeExplanation(snapshot: model.session)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(model.session?.state.readableValue ?? "unavailable")
                .font(DesignTokens.Typography.monospacedDetail)
                .opacity(0.001)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("Stream-Session-snapshot")
                .accessibilityValue(model.session?.readableValue ?? "unavailable")
                .allowsHitTesting(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.releaseInputs(cause: "background")
            }
        }
        .onChange(of: model.session?.id) { _, newValue in
            if newValue == nil {
                dismissWindow(id: "streaming")
            }
        }
        .onChange(of: model.session?.state) { _, state in
            if case .ended = state {
                dismissWindow(id: "streaming")
            }
        }
        .onDisappear {
            model.releaseInputs(cause: "disconnect")
        }
    }

    private var videoAspectRatio: CGFloat {
        if let negotiated = model.session?.negotiated, negotiated.width > 0, negotiated.height > 0 {
            return CGFloat(negotiated.width) / CGFloat(negotiated.height)
        }
        let resolution = model.session?.requested.resolution ?? model.settings.resolution
        return CGFloat(resolution.width) / CGFloat(resolution.height)
    }
}

private struct StreamWindowChrome: View {
    let snapshot: SessionSnapshot?
    let onBack: () -> Void
    let onDock: () -> Void
    let onDegrade: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.backward")
            }
            .accessibilityIdentifier("Stream-Session-back")

            Button(action: onDock) {
                Label("Dock", systemImage: "rectangle.on.rectangle")
            }
            .accessibilityIdentifier("Stream-Session-dock")

            if let snapshot, !snapshot.adjustments.isEmpty {
                Button(action: onDegrade) {
                    Label("说明", systemImage: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("Stream-Session-degrade")
                .accessibilityValue(snapshot.adjustments.map(\.summary).joined(separator: "; "))
            }

            Spacer(minLength: 0)

            if case .connecting(let stage) = snapshot?.state {
                Text("\(snapshot?.hostName ?? ""): \(stage)")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("Stream-Session-connecting")
                    .accessibilityValue("host=\(snapshot?.hostName ?? "");action=\(stage)")
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .enchronGlassControlSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-Session-controls")
    }
}

private struct StreamDegradeExplanation: View {
    let snapshot: SessionSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("显示说明")
                .font(DesignTokens.Typography.headline)
            ForEach(Array((snapshot?.adjustments ?? []).enumerated()), id: \.offset) { _, notice in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(notice.summary)
                        .font(DesignTokens.Typography.selectionHeader)
                    Text(notice.detail)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Stream-Session-degrade-explain")
        .accessibilityValue(
            (snapshot?.adjustments ?? [])
                .map { "\($0.summary)：\($0.detail)" }
                .joined(separator: " ")
        )
    }
}

private struct StreamPointerInputLayer: View {
    let videoAspectRatio: CGFloat
    let onMove: (Float, Float) -> Void
    let onClick: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let location) = phase {
                        if let normalized = Self.normalized(
                            location: location,
                            in: geometry.size,
                            videoAspectRatio: videoAspectRatio
                        ) {
                            onMove(Float(normalized.x), Float(normalized.y))
                        }
                    }
                }
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            if let normalized = Self.normalized(
                                location: value.location,
                                in: geometry.size,
                                videoAspectRatio: videoAspectRatio
                            ) {
                                onClick(normalized)
                            }
                        }
                )
        }
        .accessibilityHidden(true)
    }

    private static func normalized(
        location: CGPoint,
        in size: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGPoint? {
        guard size.width > 0, size.height > 0, videoAspectRatio > 0 else { return nil }
        let fitted: CGSize
        if size.width / size.height > videoAspectRatio {
            fitted = CGSize(width: size.height * videoAspectRatio, height: size.height)
        } else {
            fitted = CGSize(width: size.width, height: size.width / videoAspectRatio)
        }
        let origin = CGPoint(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2
        )
        let x = (location.x - origin.x) / fitted.width
        let y = (location.y - origin.y) / fitted.height
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        return CGPoint(x: x, y: y)
    }
}

private struct StreamKeyboardCapture: UIViewRepresentable {
    let onKey: (UIKeyboardHIDUsage, Bool, UIKeyModifierFlags) -> Void
    let onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> StreamKeyboardCaptureView {
        let view = StreamKeyboardCaptureView()
        view.onKey = onKey
        view.onFocusChange = onFocusChange
        return view
    }

    func updateUIView(_ uiView: StreamKeyboardCaptureView, context: Context) {
        uiView.onKey = onKey
        uiView.onFocusChange = onFocusChange
    }
}

final class StreamKeyboardCaptureView: UIView {
    var onKey: ((UIKeyboardHIDUsage, Bool, UIKeyModifierFlags) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            return
        }
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = forward(presses, down: true)
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let handled = forward(presses, down: false)
        if !handled {
            super.pressesEnded(presses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        _ = forward(presses, down: false)
        super.pressesCancelled(presses, with: event)
    }

    private func forward(_ presses: Set<UIPress>, down: Bool) -> Bool {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            onKey?(key.keyCode, down, key.modifierFlags)
            handled = true
        }
        return handled
    }
}
