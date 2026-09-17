import Foundation
import SwiftUI

private struct SpinnerArc: Shape {
    var start: CGFloat
    var end: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) * 0.38,
            startAngle: .degrees(Double(start) * 360),
            endAngle: .degrees(Double(end) * 360),
            clockwise: false
        )
        return path
    }
}

private enum MaterialCircularIndeterminateAdvance {
    static func segmentFractions(
        animationFraction: CGFloat
    ) -> (start: CGFloat, end: CGFloat) {
        let tokens = DesignTokens.LoadingSpinner.self
        let playtime = Int(animationFraction * tokens.cycleDurationMilliseconds)
        var startDegrees =
            tokens.constantRotationDegrees * Double(animationFraction)
                + tokens.tailDegreesOffset
        var endDegrees = tokens.constantRotationDegrees * Double(animationFraction)

        for cycleIndex in 0..<tokens.cyclesPerLoop {
            let expand = fractionInRange(
                playtime: playtime,
                delay: tokens.expandDelaysMilliseconds[cycleIndex],
                duration: tokens.expandCollapseDurationMilliseconds
            )
            endDegrees += Double(fastOutSlowIn(expand)) * tokens.extraDegreesPerCycle

            let collapse = fractionInRange(
                playtime: playtime,
                delay: tokens.collapseDelaysMilliseconds[cycleIndex],
                duration: tokens.expandCollapseDurationMilliseconds
            )
            startDegrees += Double(fastOutSlowIn(collapse)) * tokens.extraDegreesPerCycle
        }

        return (CGFloat(startDegrees / 360), CGFloat(endDegrees / 360))
    }

    private static func fractionInRange(
        playtime: Int,
        delay: Double,
        duration: Double
    ) -> CGFloat {
        CGFloat(max(0, min(1, (Double(playtime) - delay) / duration)))
    }

    private static func fastOutSlowIn(_ t: CGFloat) -> CGFloat {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        return unitBezierY(t, p1x: 0.4, p1y: 0, p2x: 0.2, p2y: 1)
    }

    private static func unitBezierY(
        _ t: CGFloat,
        p1x: CGFloat,
        p1y: CGFloat,
        p2x: CGFloat,
        p2y: CGFloat
    ) -> CGFloat {
        var sample = t
        for _ in 0..<5 {
            let x = bezierSample(sample, a: p1x, b: p2x) - t
            let dx = bezierDerivative(sample, a: p1x, b: p2x)
            if abs(x) < 1e-5 || abs(dx) < 1e-5 { break }
            sample -= x / dx
        }
        sample = min(1, max(0, sample))
        return bezierSample(sample, a: p1y, b: p2y)
    }

    private static func bezierSample(_ t: CGFloat, a: CGFloat, b: CGFloat) -> CGFloat {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private static func bezierDerivative(
        _ t: CGFloat,
        a: CGFloat,
        b: CGFloat
    ) -> CGFloat {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}

public struct LoadingSpinner: View {
    static let reconnectNoticeThresholdSeconds: Double = 3

    var size: CGFloat = 56
    var showBorder = true
    var sourceReadBytesPerSecond: (@MainActor () -> UInt64)?
    var sourceReadPendingSeconds: (@MainActor () -> Double)?

    @State private var cycleAnchor = Date()

    public init(
        size: CGFloat = 56,
        showBorder: Bool = true,
        sourceReadBytesPerSecond: (@MainActor () -> UInt64)? = nil,
        sourceReadPendingSeconds: (@MainActor () -> Double)? = nil
    ) {
        self.size = size
        self.showBorder = showBorder
        self.sourceReadBytesPerSecond = sourceReadBytesPerSecond
        self.sourceReadPendingSeconds = sourceReadPendingSeconds
    }

    public var body: some View {
        let lineWidth = size * 0.06
        let inset = size * 0.16

        VStack(spacing: DesignTokens.Spacing.xs) {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) {
                context in
                let elapsed = context.date.timeIntervalSince(cycleAnchor)
                let cycleSeconds =
                    DesignTokens.LoadingSpinner.cycleDurationMilliseconds / 1000
                let fraction = CGFloat(
                    (elapsed / cycleSeconds).truncatingRemainder(dividingBy: 1)
                )
                let segment = MaterialCircularIndeterminateAdvance.segmentFractions(
                    animationFraction: fraction
                )

                ZStack {
                    SpinnerArc(start: segment.start, end: segment.end)
                        .stroke(
                            DesignTokens.Theme.accent.opacity(0.15),
                            style: StrokeStyle(
                                lineWidth: lineWidth * 4,
                                lineCap: .round
                            )
                        )
                        .blur(radius: lineWidth * 2)
                        .blendMode(.screen)
                        .padding(inset)

                    SpinnerArc(start: segment.start, end: segment.end)
                        .stroke(
                            .white.opacity(0.9),
                            style: StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round
                            )
                        )
                        .padding(inset)
                }
            }
            .frame(width: size, height: size)
            .overlay {
                if showBorder {
                    Circle()
                        .strokeBorder(
                            DesignTokens.Theme.accent.opacity(0.3),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(Circle())
            .background(DesignTokens.Surface.elevated, in: Circle())

            if let sourceReadPendingSeconds {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let pendingSeconds = sourceReadPendingSeconds()
                    if pendingSeconds >= Self.reconnectNoticeThresholdSeconds {
                        Text("Reconnecting…")
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .accessibilityIdentifier(
                                "LoadingSpinner-reconnect-notice"
                            )
                    }
                }
            }

            if let sourceReadBytesPerSecond {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.sourceReadRateText(
                        bytesPerSecond: sourceReadBytesPerSecond()
                    ))
                    .font(DesignTokens.Typography.metadata.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            }
        }
    }

    static func sourceReadRateText(bytesPerSecond: UInt64) -> String {
        let value = Double(bytesPerSecond)
        switch value {
        case ..<1_000:
            return "\(bytesPerSecond) B/s"
        case ..<1_000_000:
            return String(format: "%.1f KB/s", value / 1_000)
        case ..<1_000_000_000:
            return String(format: "%.1f MB/s", value / 1_000_000)
        default:
            return String(format: "%.1f GB/s", value / 1_000_000_000)
        }
    }
}

#Preview("Loading throughput") {
    HStack(spacing: DesignTokens.Spacing.xl) {
        LoadingSpinner(sourceReadBytesPerSecond: { 0 })
        LoadingSpinner(sourceReadBytesPerSecond: { 12_400_000 })
    }
    .padding(DesignTokens.Spacing.xl)
}
