import DesignSystem
import SwiftUI
import UIKit

public struct StreamSessionContentView: View {
    @Environment(StreamingModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

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
