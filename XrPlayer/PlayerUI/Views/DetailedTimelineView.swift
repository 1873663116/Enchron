import SwiftUI

/// A precision timeline editor.
///
/// Interaction model:
/// - The center vertical line is the **playhead** — it never moves.
/// - The user **drags the track left or right** to scrub; dragging left advances time.
/// - The **zoom slider** adjusts how much time fits in the visible width.
///   Smaller window = faster seeking per pixel; larger window = coarser scrubbing.
/// - **Frame step buttons** are centered at the bottom.
/// - Actual seeking is deferred to gesture release to avoid thrashing the player.
public struct DetailedTimelineView: View {
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    let onClose: () -> Void

    // Seconds of media visible across the full track width.
    @State private var windowDuration: Double = 60

    // Local drag offset in seconds (positive = user dragged left = time increases).
    // Resets to zero after each seek commit.
    @State private var dragOffsetSeconds: Double = 0

    // Track geometry captured during gesture for coordinate math.
    @State private var trackWidth: CGFloat = 1

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    // MARK: - Derived values

    private var duration: Double { videoViewModel.playbackPosition.duration }

    /// The position displayed while dragging (may differ from the committed seek position).
    private var displayPosition: Double {
        let raw = videoViewModel.playbackPosition.seconds + dragOffsetSeconds
        return max(0, min(duration, raw))
    }

    private var pixelsPerSecond: CGFloat {
        guard windowDuration > 0, trackWidth > 0 else { return 1 }
        return trackWidth / CGFloat(windowDuration)
    }

    private var minWindowDuration: Double { min(max(duration, 5), 5) }

    private var maxWindowDuration: Double { max(duration, 30) }

    private var normalizedZoom: Double {
        guard maxWindowDuration > minWindowDuration else { return 1 }
        return (maxWindowDuration - windowDuration) / (maxWindowDuration - minWindowDuration)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            trackRow
                .padding(.horizontal, 20)

            currentTimeLabel
                .padding(.top, 12)

            zoomSliderRow
                .padding(.horizontal, 20)
                .padding(.top, 12)

            frameStepRow
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            windowDuration = min(maxWindowDuration, max(minWindowDuration, windowDuration))
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack {
            Text("精确时间轴")
                .font(.headline)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var trackRow: some View {
        GeometryReader { geo in
            let availableWidth = max(geo.size.width, 260)
            let bandHeight: CGFloat = 84
            let timelineWidth = timelineBandWidth(for: availableWidth)
            let interval = tickInterval(for: windowDuration, width: timelineWidth)
            let centerTime = displayPosition
            let firstTick = (floor(centerTime / interval) - 1) * interval

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.01))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .frame(height: bandHeight + 34)

                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.11)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: timelineWidth, height: bandHeight)

                    timelineBandTicks(
                        firstTick: firstTick,
                        interval: interval,
                        centerTime: centerTime,
                        width: timelineWidth,
                        height: bandHeight
                    )

                    HStack {
                        Text(formatTime(max(0, centerTime - (windowDuration / 2))))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(min(duration, centerTime + (windowDuration / 2))))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: timelineWidth, height: bandHeight, alignment: .bottom)
                    .padding(.bottom, 8)
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: bandHeight + 18)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 0)

                Image(systemName: "triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(180))
                    .offset(y: -(bandHeight / 2 + 10))
            }
            .frame(width: availableWidth, height: bandHeight + 36, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let pps = pixelsPerSecond(width: timelineWidth)
                        guard pps > 0 else { return }
                        let deltaSeconds = Double(-value.translation.width / pps)
                        dragOffsetSeconds = deltaSeconds
                    }
                    .onEnded { _ in
                        let target = videoViewModel.playbackPosition.seconds + dragOffsetSeconds
                        let clamped = max(0, min(duration, target))
                        dragOffsetSeconds = 0
                        videoViewModel.seek(to: clamped)
                    }
            )
            .onAppear { trackWidth = timelineWidth }
            .onChange(of: geo.size.width) { _, _ in
                trackWidth = timelineBandWidth(for: max(geo.size.width, 260))
            }
        }
        .frame(height: 128)
    }

    private var currentTimeLabel: some View {
        VStack(spacing: 4) {
            Text(formatTimeWithFrames(displayPosition))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(dragOffsetSeconds != 0 ? .orange : .primary)
                .animation(.none, value: dragOffsetSeconds)

            Text("固定中心指针，拖动的是时间带；松手后才提交精准 seek")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var zoomSliderRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(
                    value: $windowDuration,
                    in: minWindowDuration...maxWindowDuration,
                    step: 5
                )
                .tint(.secondary)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            HStack {
                Text("可见时间窗")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(windowDuration))s")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var frameStepRow: some View {
        HStack(spacing: 48) {
            Button {
                videoViewModel.frameStepBackward()
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                videoViewModel.frameStepForward()
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func pixelsPerSecond(width: CGFloat) -> CGFloat {
        guard windowDuration > 0, width > 0 else { return 1 }
        return width / CGFloat(windowDuration)
    }

    private func timelineBandWidth(for availableWidth: CGFloat) -> CGFloat {
        let minBandWidth = min(availableWidth, max(240, availableWidth * 0.42))
        let saturation = min(1, normalizedZoom * 1.35)
        return minBandWidth + (availableWidth - minBandWidth) * CGFloat(saturation)
    }

    private func tickInterval(for window: Double, width: CGFloat) -> Double {
        // Target roughly one tick per 80pt
        let targetTicks = max(1, Double(width) / 80)
        let rawInterval = window / targetTicks
        // Snap to a nice value
        let nice: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return nice.first { $0 >= rawInterval } ?? rawInterval
    }

    private func timelineTicks(
        firstTick: Double,
        interval: Double,
        centerTime: Double
    ) -> [Double] {
        guard interval > 0 else { return [] }
        var ticks: [Double] = []
        var t = firstTick
        let extraWindow = windowDuration * 0.5
        while t <= centerTime + extraWindow + interval {
            if t >= 0 { ticks.append(t) }
            t += interval
        }
        return ticks
    }

    @ViewBuilder
    private func timelineBandTicks(
        firstTick: Double,
        interval: Double,
        centerTime: Double,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let ticks = timelineTicks(
            firstTick: firstTick,
            interval: interval,
            centerTime: centerTime
        )

        ZStack(alignment: .leading) {
            ForEach(ticks, id: \.self) { tick in
                let xPos = width / 2 + CGFloat(tick - centerTime) * pixelsPerSecond(width: width)
                if xPos >= 0 && xPos <= width {
                    VStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.white.opacity(tick == centerTime ? 0.95 : 0.45))
                            .frame(width: 1, height: tick == centerTime ? 26 : 16)
                        Text(formatTime(tick))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                    .position(x: xPos, y: height / 2 - 4)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func formatTimeWithFrames(_ seconds: Double) -> String {
        let fps = videoViewModel.currentMediaProfile?.frameRate ?? 0
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if fps > 0 {
            let frame = Int(seconds.truncatingRemainder(dividingBy: 1) * fps)
            return String(format: "%02d:%02d:%02d.%02d", h, m, s, frame)
        }
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
