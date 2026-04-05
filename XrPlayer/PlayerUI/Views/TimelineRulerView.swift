import SwiftUI

/// Canvas-drawn time ruler with tick marks, time labels, and a fixed-center
/// playhead indicator for the NLE timeline panel.
///
/// Built on `DetailedTimelineGeometry` for all time↔position math.
/// The playhead stays fixed at horizontal center; the ruler scrolls beneath it.
///
/// - Playhead color: white normally, `Color.enchronTertiary` when seeking.
/// - Tick density adapts to zoom level automatically.
struct TimelineRulerView: View {

    let duration: Double
    let currentTime: Double
    let isSeeking: Bool

    /// Zoom level 0…1 (0 = fully zoomed out, 1 = fully zoomed in).
    /// When `nil`, a sensible default is chosen based on `duration`.
    var zoomLevel: Double?

    // MARK: - Layout

    private let rulerHeight: CGFloat = 40
    private let majorTickHeight: CGFloat = 16
    private let minorTickHeight: CGFloat = 8
    private let labelAreaHeight: CGFloat = 16

    /// Resolved zoom: use explicit value or compute a default from duration.
    private var resolvedZoom: Double {
        if let zoomLevel { return zoomLevel }
        return Self.defaultZoom(for: duration)
    }

    /// Short videos get a higher default zoom so ticks are readable;
    /// long videos default to a lower zoom so the whole timeline is navigable.
    static func defaultZoom(for duration: Double) -> Double {
        switch duration {
        case ..<30:    return 0.8   // very short
        case ..<300:   return 0.5   // 30s – 5min
        case ..<3600:  return 0.3   // 5min – 1hr
        case ..<10800: return 0.15  // 1hr – 3hr
        default:       return 0.1   // 3hr+
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = proxy.size.width
            let geo = DetailedTimelineGeometry(
                viewportWidth: viewportWidth,
                duration: duration,
                zoomLevel: resolvedZoom
            )
            let intervals = geo.tickIntervals()

            Canvas { context, size in
                let originX = playheadX(in: size) - geo.xPosition(for: currentTime)

                drawTicks(
                    context: &context,
                    size: size,
                    originX: originX,
                    geo: geo,
                    intervals: intervals
                )

                drawPlayhead(context: &context, size: size)
            }
            .frame(height: rulerHeight)
            .overlay(alignment: .bottom) {
                tickLabelsOverlay(
                    viewportWidth: viewportWidth,
                    geo: geo,
                    majorInterval: intervals.major
                )
            }
        }
        .frame(height: rulerHeight + labelAreaHeight)
    }

    // MARK: - Canvas Drawing

    private struct TickStyle {
        let interval: Double
        let height: CGFloat
        let color: Color
        let lineWidth: CGFloat
    }

    private func drawTicks(
        context: inout GraphicsContext,
        size: CGSize,
        originX: CGFloat,
        geo: DetailedTimelineGeometry,
        intervals: (minor: Double, major: Double)
    ) {
        let centerY = size.height / 2
        let styles: [TickStyle] = [
            TickStyle(interval: intervals.minor, height: minorTickHeight,
                      color: .white.opacity(0.2), lineWidth: 0.5),
            TickStyle(interval: intervals.major, height: majorTickHeight,
                      color: .white.opacity(0.45), lineWidth: 1.0)
        ]

        for style in styles {
            drawTickSet(
                context: &context,
                style: style,
                originX: originX,
                geo: geo,
                size: size,
                centerY: centerY
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func drawTickSet(
        context: inout GraphicsContext,
        style: TickStyle,
        originX: CGFloat,
        geo: DetailedTimelineGeometry,
        size: CGSize,
        centerY: CGFloat
    ) {
        guard style.interval > 0, duration > 0 else { return }

        let tickCount = Int(duration / style.interval) + 1
        for i in 0...tickCount {
            let time = Double(i) * style.interval
            guard time <= duration else { break }
            let x = originX + geo.xPosition(for: time)

            // Cull off-screen ticks
            guard x >= -10, x <= size.width + 10 else { continue }

            let halfTick = style.height / 2
            var path = Path()
            path.move(to: CGPoint(x: x, y: centerY - halfTick))
            path.addLine(to: CGPoint(x: x, y: centerY + halfTick))
            context.stroke(path, with: .color(style.color), lineWidth: style.lineWidth)
        }
    }

    private func drawPlayhead(context: inout GraphicsContext, size: CGSize) {
        let x = playheadX(in: size)
        let color: Color = isSeeking ? .enchronTertiary : .white

        // Vertical line
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(color), lineWidth: 1.5)

        // Triangle indicator at top
        let triangleSize: CGFloat = 5
        var triangle = Path()
        triangle.move(to: CGPoint(x: x - triangleSize, y: 0))
        triangle.addLine(to: CGPoint(x: x + triangleSize, y: 0))
        triangle.addLine(to: CGPoint(x: x, y: triangleSize))
        triangle.closeSubpath()
        context.fill(triangle, with: .color(color))
    }

    // MARK: - Labels Overlay

    @ViewBuilder
    private func tickLabelsOverlay(
        viewportWidth: CGFloat,
        geo: DetailedTimelineGeometry,
        majorInterval: Double
    ) -> some View {
        let originX = viewportWidth / 2 - geo.xPosition(for: currentTime)

        ZStack(alignment: .topLeading) {
            ForEach(majorTickTimes(interval: majorInterval), id: \.self) { time in
                let x = originX + geo.xPosition(for: time)

                if x >= 20, x <= viewportWidth - 20 {
                    Text(PlaybackTimeFormatter.clock(time))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .position(x: x, y: labelAreaHeight / 2)
                }
            }
        }
        .frame(height: labelAreaHeight)
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

#Preview("1hr video") {
    TimelineRulerView(
        duration: 3600,
        currentTime: 125.5,
        isSeeking: false
    )
    .padding()
    .glassBackgroundEffect()
}

#Preview("Short video - seeking") {
    TimelineRulerView(
        duration: 8,
        currentTime: 3.2,
        isSeeking: true
    )
    .padding()
    .glassBackgroundEffect()
}

#Preview("3hr+ video") {
    TimelineRulerView(
        duration: 12000,
        currentTime: 4500,
        isSeeking: false
    )
    .padding()
    .glassBackgroundEffect()
}
