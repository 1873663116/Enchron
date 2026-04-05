import SwiftUI

/// Canvas-drawn thumbnail placeholder strip for the NLE timeline.
///
/// Renders solid-color placeholder rectangles that vary by timestamp position,
/// providing a visual guide for timeline scrubbing. A `DragGesture` on the strip
/// drives playback seeking via the `onSeek` callback.
///
/// Built on `DetailedTimelineGeometry` for all time-position math (same as
/// `TimelineRulerView`). Actual thumbnail generation (mpv screenshot or
/// AVAssetImageGenerator) is deferred — placeholders are used for now.
struct ThumbStripView: View {

    let duration: Double
    let currentTime: Double
    let zoomLevel: Double

    /// Called with the target time when the user drags on the strip.
    var onSeek: ((Double) -> Void)?

    // MARK: - Layout

    private let stripHeight: CGFloat = 48
    private let thumbWidth: CGFloat = 64
    private let thumbGap: CGFloat = 2
    private let thumbCornerRadius: CGFloat = 4

    // MARK: - Drag State

    @State private var isDragging = false
    @State private var dragStartTime: Double = 0

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = proxy.size.width
            let geo = DetailedTimelineGeometry(
                viewportWidth: viewportWidth,
                duration: duration,
                zoomLevel: zoomLevel
            )

            Canvas { context, size in
                let originX = size.width / 2 - geo.xPosition(for: currentTime)
                drawThumbnailPlaceholders(
                    context: &context,
                    size: size,
                    originX: originX,
                    geo: geo
                )
            }
            .frame(height: stripHeight)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartTime = currentTime
                        }
                        let geo = DetailedTimelineGeometry(
                            viewportWidth: viewportWidth,
                            duration: duration,
                            zoomLevel: zoomLevel
                        )
                        let timeDelta = -Double(value.translation.width) * geo.secondsPerPoint
                        let targetTime = max(0, min(duration, dragStartTime + timeDelta))
                        onSeek?(targetTime)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: stripHeight)
    }

    // MARK: - Canvas Drawing

    private func drawThumbnailPlaceholders(
        context: inout GraphicsContext,
        size: CGSize,
        originX: CGFloat,
        geo: DetailedTimelineGeometry
    ) {
        guard duration > 0 else { return }

        let thumbStep = thumbWidth + thumbGap
        let thumbCount = Int(geo.timelineWidth / thumbStep) + 1

        for i in 0..<thumbCount {
            let thumbX = originX + CGFloat(i) * thumbStep
            let thumbEndX = thumbX + thumbWidth

            // Cull off-screen thumbnails
            guard thumbEndX >= 0, thumbX <= size.width else { continue }

            let time = Double(i) * thumbStep * geo.secondsPerPoint
            let hue = thumbnailHue(for: time)

            let rect = CGRect(
                x: thumbX,
                y: 0,
                width: thumbWidth,
                height: size.height
            )
            let path = RoundedRectangle(cornerRadius: thumbCornerRadius, style: .continuous)
                .path(in: rect)

            context.fill(path, with: .color(Color(hue: hue, saturation: 0.15, brightness: 0.18)))

            // Subtle top highlight
            let highlightRect = CGRect(x: thumbX, y: 0, width: thumbWidth, height: 1)
            context.fill(Path(highlightRect), with: .color(.white.opacity(0.06)))
        }
    }

    // MARK: - Placeholder Hue

    /// Generates a subtle hue variation based on video timestamp position,
    /// giving visual differentiation to each placeholder segment.
    private func thumbnailHue(for time: Double) -> Double {
        guard duration > 0 else { return 0.6 }
        let normalizedPosition = time / duration
        // Sweep through a narrow hue range (blue-purple) for subtle variation
        return 0.6 + normalizedPosition * 0.12
    }
}

#Preview("1hr video") {
    ThumbStripView(
        duration: 3600,
        currentTime: 125.5,
        zoomLevel: 0.3
    )
    .padding()
    .glassBackgroundEffect()
}

#Preview("Short video") {
    ThumbStripView(
        duration: 8,
        currentTime: 3.2,
        zoomLevel: 0.8
    )
    .padding()
    .glassBackgroundEffect()
}
