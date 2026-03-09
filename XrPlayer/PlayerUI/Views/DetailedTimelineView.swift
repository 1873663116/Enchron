import SwiftUI

/// A precision timeline editor using a "fixed center axis + stretchable timeline body + viewport clip" model.
///
/// Interaction model:
/// - The center vertical line is the **playhead** — it never moves.
/// - The user **drags the timeline body** left or right to scrub.
/// - The **zoom slider** adjusts the timeline body width (longer = more detail).
/// - Actual seeking uses a throttled preview for local files (max 8Hz, min 0.25s change),
///   and deferred-to-release for remote files (WebDAV / SMB).
/// - Frame step buttons are centered at the bottom.
public struct DetailedTimelineView: View {
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    let onClose: () -> Void

    // MARK: - Timeline geometry state

    /// Zoom level: 0.0 = fully zoomed out, 1.0 = fully zoomed in.
    @State private var zoomLevel: Double = 0.3

    /// Offset of the timeline body relative to the center axis, in points.
    /// Positive means the timeline has been dragged to the right (earlier time at center).
    @State private var contentOffsetX: CGFloat = 0

    /// Accumulated drag translation during an active gesture.
    @State private var dragTranslation: CGFloat = 0

    /// Whether the user is currently dragging.
    @State private var isDragging: Bool = false

    /// Container (viewport) width captured from GeometryReader.
    @State private var viewportWidth: CGFloat = 600

    // MARK: - Throttled seek state (local files only)

    @State private var lastThrottledSeekTime: Date = .distantPast
    @State private var lastThrottledSeekPosition: Double = -1

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    // MARK: - Derived values

    private var duration: Double { max(videoViewModel.playbackPosition.duration, 0.1) }

    /// Whether the current playback source is remote (WebDAV/SMB).
    private var isRemoteSource: Bool {
        guard let url = videoViewModel.currentPlaybackURL else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "smb" || scheme == "http" || scheme == "https"
    }

    /// Timeline body width: at minimum zoom = viewport * 0.5, grows with zoom.
    private var timelineWidth: CGFloat {
        let minWidth = viewportWidth * 0.5
        let maxWidth = viewportWidth * 4.0
        return minWidth + (maxWidth - minWidth) * CGFloat(zoomLevel)
    }

    /// Seconds per point on the timeline body.
    private var secondsPerPoint: Double {
        guard timelineWidth > 0 else { return 1 }
        return duration / Double(timelineWidth)
    }

    /// The effective content offset (base + drag).
    private var effectiveOffsetX: CGFloat {
        clampedOffset(contentOffsetX + dragTranslation)
    }

    /// Current time at the center axis.
    private var centerTime: Double {
        // The center axis maps to a position on the timeline body.
        // When offset = 0, center axis is at timeline midpoint.
        // contentOffsetX positive = timeline shifted right = center sees earlier time.
        let centerPointOnTimeline = timelineWidth / 2 - effectiveOffsetX
        let time = Double(centerPointOnTimeline) * secondsPerPoint
        return max(0, min(duration, time))
    }

    // MARK: - Clamping

    /// Clamp offset so that:
    /// - At first frame: center axis aligns with timeline start.
    /// - At last frame: center axis aligns with timeline end.
    private func clampedOffset(_ offset: CGFloat) -> CGFloat {
        // Center axis at timeline start: centerPointOnTimeline = 0
        //   → timelineWidth/2 - offset = 0 → offset = timelineWidth/2
        let maxOffset = timelineWidth / 2

        // Center axis at timeline end: centerPointOnTimeline = timelineWidth
        //   → timelineWidth/2 - offset = timelineWidth → offset = -timelineWidth/2
        let minOffset = -timelineWidth / 2

        return max(minOffset, min(maxOffset, offset))
    }

    /// Convert a time position to a content offset.
    private func offsetForTime(_ time: Double) -> CGFloat {
        let pointOnTimeline = CGFloat(time / secondsPerPoint)
        return timelineWidth / 2 - pointOnTimeline
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
            syncOffsetToCurrentTime()
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
            let containerWidth = max(geo.size.width, 260)
            let bandHeight: CGFloat = 84

            ZStack {
                // Outer container (viewport)
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.01))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .frame(height: bandHeight + 34)

                // Timeline body (clipped to viewport)
                timelineBody(
                    containerWidth: containerWidth,
                    bandHeight: bandHeight
                )
                .frame(width: containerWidth, height: bandHeight + 34)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                // Center axis playhead
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
            .frame(width: containerWidth, height: bandHeight + 36, alignment: .center)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onAppear {
                viewportWidth = containerWidth
            }
            .onChange(of: geo.size.width) { _, newWidth in
                let oldTime = centerTime
                viewportWidth = max(newWidth, 260)
                contentOffsetX = offsetForTime(oldTime)
            }
        }
        .frame(height: 128)
    }

    @ViewBuilder
    private func timelineBody(containerWidth: CGFloat, bandHeight: CGFloat) -> some View {
        let tlWidth = timelineWidth
        let interval = tickInterval(for: duration, width: tlWidth)
        let xCenter = containerWidth / 2

        // The timeline body is positioned so that the point corresponding to
        // centerTime sits at the container center.
        let timelineBodyCenter = tlWidth / 2 - effectiveOffsetX

        // Offset to apply so timeline body center maps to container center.
        let shiftX = xCenter - timelineBodyCenter

        ZStack(alignment: .leading) {
            // Timeline background band
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
                .frame(width: tlWidth, height: bandHeight)

            // Ticks drawn in timeline body coordinate system
            timelineBodyTicks(
                width: tlWidth,
                height: bandHeight,
                interval: interval
            )

            // Edge time labels
            HStack {
                Text(formatTime(0))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(width: tlWidth, height: bandHeight, alignment: .bottom)
            .padding(.bottom, 8)
        }
        .offset(x: shiftX)
    }

    @ViewBuilder
    private func timelineBodyTicks(
        width: CGFloat,
        height: CGFloat,
        interval: Double
    ) -> some View {
        let firstTick = max(0, floor(0 / interval) * interval)
        var ticks: [Double] = []
        let _ = {
            var t = firstTick
            while t <= duration + interval * 0.5 {
                if t >= 0 && t <= duration {
                    ticks.append(t)
                }
                t += interval
            }
        }()

        ZStack(alignment: .leading) {
            ForEach(ticks, id: \.self) { tick in
                let xPos = CGFloat(tick / secondsPerPoint)
                let isNearCenter = abs(tick - centerTime) < interval * 0.1
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.white.opacity(isNearCenter ? 0.95 : 0.45))
                        .frame(width: 1, height: isNearCenter ? 26 : 16)
                    Text(formatTime(tick))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.84))
                }
                .position(x: xPos, y: height / 2 - 4)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var currentTimeLabel: some View {
        VStack(spacing: 4) {
            Text(formatTimeWithFrames(centerTime))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(isDragging ? .orange : .primary)
                .animation(.none, value: isDragging)

            Text(isRemoteSource
                 ? "固定中心指针，拖动时间轴；松手后提交 seek"
                 : "固定中心指针，拖动时间轴；实时预览 seek")
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
                    value: Binding(
                        get: { zoomLevel },
                        set: { newZoom in
                            let oldTime = centerTime
                            zoomLevel = newZoom
                            // Preserve center time after zoom change.
                            contentOffsetX = offsetForTime(oldTime)
                        }
                    ),
                    in: 0...1,
                    step: 0.01
                )
                .tint(.secondary)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            HStack {
                Text("缩放")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", zoomLevel * 100))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var frameStepRow: some View {
        HStack(spacing: 48) {
            Button {
                videoViewModel.frameStepBackward()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    syncOffsetToCurrentTime()
                }
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title2)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                videoViewModel.frameStepForward()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    syncOffsetToCurrentTime()
                }
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title2)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                isDragging = true
                dragTranslation = value.translation.width

                // Throttled seek for local files
                if !isRemoteSource {
                    throttledSeek()
                }
            }
            .onEnded { _ in
                isDragging = false
                contentOffsetX = effectiveOffsetX
                dragTranslation = 0

                // Commit final seek
                let target = centerTime
                videoViewModel.seek(to: target)
                lastThrottledSeekPosition = -1
            }
    }

    /// Local-file throttled seek: max 8Hz, min 0.25s position change.
    private func throttledSeek() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastThrottledSeekTime)
        guard elapsed >= 0.125 else { return } // 8Hz

        let target = centerTime
        if lastThrottledSeekPosition >= 0 && abs(target - lastThrottledSeekPosition) < 0.25 {
            return
        }

        lastThrottledSeekTime = now
        lastThrottledSeekPosition = target
        videoViewModel.seek(to: target)
    }

    // MARK: - Sync

    /// Set contentOffsetX so that the center axis points at the current playback position.
    private func syncOffsetToCurrentTime() {
        let time = videoViewModel.playbackPosition.seconds
        contentOffsetX = offsetForTime(time)
    }

    // MARK: - Helpers

    private func tickInterval(for totalDuration: Double, width: CGFloat) -> Double {
        let targetTicks = max(1, Double(width) / 80)
        let rawInterval = totalDuration / targetTicks
        let nice: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
        return nice.first { $0 >= rawInterval } ?? rawInterval
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
