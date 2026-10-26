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
                onMove: { x, y in model.sendPointerMove(normalizedX: x, normalizedY: y) },
                onClick: { position in
                    model.releaseInputs(cause: "pointer-control")
                    model.sendGestureClick(
                        normalizedX: Float(position.x),
                        normalizedY: Float(position.y)
                    )
                }
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
