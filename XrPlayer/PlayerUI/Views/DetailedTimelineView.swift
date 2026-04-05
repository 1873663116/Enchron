import SwiftUI

/// A precision timeline visualization that appears during slider drag operations.
/// Uses `DetailedTimelineGeometry` to render tick marks at appropriate intervals
/// and shows a playhead indicator at the current drag position.
struct DetailedTimelineView: View {
    let duration: Double
    let currentTime: Double
    let isDragging: Bool
    let dragTime: Double

    private let viewportWidth: CGFloat = 600
    private let timelineHeight: CGFloat = 40
    private let majorTickHeight: CGFloat = 16
    private let minorTickHeight: CGFloat = 8

    private var geometry: DetailedTimelineGeometry {
        DetailedTimelineGeometry(
            viewportWidth: viewportWidth,
            duration: duration,
            zoomLevel: 0.5
        )
    }

    private var displayTime: Double {
        isDragging ? dragTime : currentTime
    }

    var body: some View {
        let intervals = geometry.tickIntervals()
        let timelineWidth = geometry.timelineWidth

        Canvas { context, size in
            let originX = playheadX(in: size) - geometry.xPosition(for: displayTime)

            drawTicks(
                context: &context,
                size: size,
                originX: originX,
                timelineWidth: timelineWidth,
                intervals: intervals
            )

            drawPlayhead(context: &context, size: size)
        }
        .frame(height: timelineHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
        .overlay(alignment: .top) {
            tickLabelsOverlay(intervals: intervals, timelineWidth: timelineWidth)
        }
    }

    // MARK: - Canvas Drawing

    private func drawTicks(
        context: inout GraphicsContext,
        size: CGSize,
        originX: CGFloat,
        timelineWidth: CGFloat,
        intervals: (minor: Double, major: Double)
    ) {
        let centerY = size.height / 2

        // Minor ticks
        drawTickSet(
            context: &context,
            interval: intervals.minor,
            originX: originX,
            timelineWidth: timelineWidth,
            centerY: centerY,
            tickHeight: minorTickHeight,
            color: .white.opacity(0.2),
            lineWidth: 0.5
        )

        // Major ticks
        drawTickSet(
            context: &context,
            interval: intervals.major,
            originX: originX,
            timelineWidth: timelineWidth,
            centerY: centerY,
            tickHeight: majorTickHeight,
            color: .white.opacity(0.45),
            lineWidth: 1.0
        )
    }

    private func drawTickSet(
        context: inout GraphicsContext,
        interval: Double,
        originX: CGFloat,
        timelineWidth: CGFloat,
        centerY: CGFloat,
        tickHeight: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        guard interval > 0, duration > 0 else { return }

        let tickCount = Int(duration / interval) + 1
        for i in 0...tickCount {
            let time = Double(i) * interval
            guard time <= duration else { break }
            let x = originX + geometry.xPosition(for: time)

            guard x >= -10, x <= viewportWidth + 10 else { continue }

            let halfTick = tickHeight / 2
            var path = Path()
            path.move(to: CGPoint(x: x, y: centerY - halfTick))
            path.addLine(to: CGPoint(x: x, y: centerY + halfTick))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func drawPlayhead(context: inout GraphicsContext, size: CGSize) {
        let x = playheadX(in: size)
        let color: Color = isDragging ? .orange : .white

        // Vertical line
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(color), lineWidth: 1.5)

        // Small diamond indicator at center
        let cy = size.height / 2
        let diamondSize: CGFloat = 4
        var diamond = Path()
        diamond.move(to: CGPoint(x: x, y: cy - diamondSize))
        diamond.addLine(to: CGPoint(x: x + diamondSize, y: cy))
        diamond.addLine(to: CGPoint(x: x, y: cy + diamondSize))
        diamond.addLine(to: CGPoint(x: x - diamondSize, y: cy))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(color))
    }

    // MARK: - Labels Overlay

    @ViewBuilder
    private func tickLabelsOverlay(
        intervals: (minor: Double, major: Double),
        timelineWidth: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let originX = playheadX(in: size) - geometry.xPosition(for: displayTime)

            ZStack(alignment: .topLeading) {
                ForEach(majorTickTimes(interval: intervals.major), id: \.self) { time in
                    let x = originX + geometry.xPosition(for: time)

                    if x >= 20, x <= viewportWidth - 20 {
                        Text(PlaybackTimeFormatter.clock(time))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .position(x: x, y: timelineHeight + 8)
                    }
                }
            }
        }
        .frame(height: timelineHeight + 18)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func playheadX(in size: CGSize) -> CGFloat {
        size.width / 2
    }

    private func majorTickTimes(interval: Double) -> [Double] {
        guard interval > 0, duration > 0 else { return [] }
        let count = Int(duration / interval) + 1
        return (0...count).map { Double($0) * interval }.filter { $0 <= duration }
    }
}

#Preview {
    DetailedTimelineView(
        duration: 3600,
        currentTime: 120,
        isDragging: true,
        dragTime: 125.5
    )
    .padding()
    .glassBackgroundEffect()
}
