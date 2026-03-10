import SwiftUI

/// A precision timeline editor using a "fixed center axis + stretchable timeline body + viewport clip" model.
///
/// Interaction model:
/// - The center vertical line is the playhead and never moves.
/// - The user drags the timeline body left or right to scrub.
/// - Zoom stretches the timeline body itself while the viewport stays fixed.
/// - Local files preview seek at most 8Hz; remote files only seek on gesture end.
public struct DetailedTimelineView: View {
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    let onClose: () -> Void

    @State private var timelineWidth: CGFloat = 0
    @State private var contentOffsetX: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var viewportWidth: CGFloat = 600

    @State private var lastThrottledSeekTime: Date = .distantPast
    @State private var lastThrottledSeekPosition: Double = -1

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var duration: Double {
        max(videoViewModel.playbackPosition.duration, 0.1)
    }

    private var geometryModel: DetailedTimelineGeometry {
        timelineGeometry(for: viewportWidth)
    }

    private var effectiveOffsetX: CGFloat {
        geometryModel.clampedContentOffset(contentOffsetX + dragTranslation)
    }

    private var centerTime: Double {
        geometryModel.time(atContentOffset: effectiveOffsetX)
    }

    private var currentZoomLevel: Double {
        geometryModel.zoomLevel(for: geometryModel.timelineWidth)
    }

    private var isRemoteSource: Bool {
        guard let url = videoViewModel.currentPlaybackURL else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "smb" || scheme == "http" || scheme == "https"
    }

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
            if timelineWidth == 0 {
                timelineWidth = DetailedTimelineGeometry(
                    viewportWidth: viewportWidth,
                    duration: duration,
                    zoomLevel: 0
                ).timelineWidth
            }
            syncOffsetToCurrentTime()
        }
        .onChange(of: videoViewModel.playbackPosition.seconds) { _, _ in
            guard !isDragging else { return }
            syncOffsetToCurrentTime()
        }
        .onChange(of: videoViewModel.playbackPosition.duration) { _, _ in
            if timelineWidth == 0 {
                timelineWidth = DetailedTimelineGeometry(
                    viewportWidth: viewportWidth,
                    duration: duration,
                    zoomLevel: 0
                ).timelineWidth
            }
            guard !isDragging else { return }
            syncOffsetToCurrentTime()
        }
    }

    private var headerRow: some View {
        HStack {
            Text("精确时间轴")
                .font(.headline)
            Spacer()
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 64))
        }
    }

    private var trackRow: some View {
        GeometryReader { geo in
            let containerWidth = max(geo.size.width, 260)
            let bandHeight: CGFloat = 84
            let geometry = timelineGeometry(for: containerWidth)

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .frame(height: bandHeight + 34)

                timelineBody(geometry: geometry, bandHeight: bandHeight)
                    .frame(width: containerWidth, height: bandHeight + 34)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

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
                updateViewportWidth(containerWidth)
            }
            .onChange(of: geo.size.width) { _, newWidth in
                updateViewportWidth(max(newWidth, 260))
            }
        }
        .frame(height: 128)
    }

    @ViewBuilder
    private func timelineBody(
        geometry: DetailedTimelineGeometry,
        bandHeight: CGFloat
    ) -> some View {
        let tickIntervals = geometry.tickIntervals()

        ZStack(alignment: .leading) {
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
                .frame(width: geometry.timelineWidth, height: bandHeight)

            timelineBodyTicks(
                geometry: geometry,
                height: bandHeight,
                minorInterval: tickIntervals.minor,
                majorInterval: tickIntervals.major
            )

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
            .frame(width: geometry.timelineWidth, height: bandHeight, alignment: .bottom)
            .padding(.bottom, 8)
        }
        .offset(x: geometry.timelineBodyLeadingX(for: effectiveOffsetX))
    }

    @ViewBuilder
    private func timelineBodyTicks(
        geometry: DetailedTimelineGeometry,
        height: CGFloat,
        minorInterval: Double,
        majorInterval: Double
    ) -> some View {
        let ticks = tickValues(step: minorInterval)

        ZStack(alignment: .leading) {
            ForEach(ticks, id: \.self) { tick in
                let xPosition = geometry.xPosition(for: tick)
                let isNearCenter = abs(tick - centerTime) <= max(minorInterval, geometry.secondsPerPoint * 10)
                let isMajorTick = isMultiple(tick, of: majorInterval)

                VStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.white.opacity(isNearCenter ? 0.95 : 0.45))
                        .frame(width: 1, height: isNearCenter ? 28 : (isMajorTick ? 20 : 12))

                    if isMajorTick {
                        Text(formatTime(tick))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.84))
                    }
                }
                .position(x: xPosition, y: height / 2 - (isMajorTick ? 2 : 8))
            }
        }
        .frame(width: geometry.timelineWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var currentTimeLabel: some View {
        VStack(spacing: 4) {
            Text(formatTimeWithFrames(isDragging ? centerTime : videoViewModel.playbackPosition.seconds))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(isDragging ? .orange : .primary)
                .animation(.none, value: isDragging)

            Text(
                isRemoteSource
                    ? "固定中心指针，拖动时间轴；松手后提交 seek"
                    : "固定中心指针，拖动时间轴；实时预览 seek"
            )
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
                        get: { currentZoomLevel },
                        set: { updateTimelineZoom($0) }
                    ),
                    in: 0...1
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
                Text(String(format: "%.0f%%", currentZoomLevel * 100))
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
                    .foregroundStyle(.white)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 72, prominence: .primary))

            Button {
                videoViewModel.frameStepForward()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    syncOffsetToCurrentTime()
                }
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 72, prominence: .primary))
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                isDragging = true
                dragTranslation = value.translation.width

                if !isRemoteSource {
                    throttledSeek()
                }
            }
            .onEnded { _ in
                let finalOffset = effectiveOffsetX
                let target = geometryModel.time(atContentOffset: finalOffset)

                isDragging = false
                contentOffsetX = finalOffset
                dragTranslation = 0

                videoViewModel.seek(to: target)
                lastThrottledSeekPosition = -1
            }
    }

    private func throttledSeek() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastThrottledSeekTime)
        guard elapsed >= 0.125 else { return }

        let target = centerTime
        if lastThrottledSeekPosition >= 0 && abs(target - lastThrottledSeekPosition) < 0.25 {
            return
        }

        lastThrottledSeekTime = now
        lastThrottledSeekPosition = target
        videoViewModel.seek(to: target)
    }

    private func syncOffsetToCurrentTime() {
        if timelineWidth == 0 {
            timelineWidth = DetailedTimelineGeometry(
                viewportWidth: viewportWidth,
                duration: duration,
                zoomLevel: 0.3
            ).timelineWidth
        }
        contentOffsetX = geometryModel.contentOffset(for: videoViewModel.playbackPosition.seconds)
    }

    private func timelineGeometry(for viewportWidth: CGFloat) -> DetailedTimelineGeometry {
        let width = timelineWidth > 0
            ? timelineWidth
            : DetailedTimelineGeometry(
                viewportWidth: viewportWidth,
                duration: duration,
                zoomLevel: 0.3
            ).timelineWidth

        return DetailedTimelineGeometry(
            viewportWidth: viewportWidth,
            duration: duration,
            timelineWidth: width
        )
    }

    private func updateViewportWidth(_ newWidth: CGFloat) {
        let clampedWidth = max(newWidth, 260)
        let preservedTime = isDragging ? centerTime : videoViewModel.playbackPosition.seconds
        let preservedZoom = timelineWidth > 0 ? currentZoomLevel : 0.3

        viewportWidth = clampedWidth
        let updatedGeometry = DetailedTimelineGeometry(
            viewportWidth: clampedWidth,
            duration: duration,
            zoomLevel: preservedZoom
        )
        timelineWidth = updatedGeometry.timelineWidth
        contentOffsetX = updatedGeometry.contentOffset(for: preservedTime)
    }

    private func updateTimelineZoom(_ zoomLevel: Double) {
        let preservedTime = centerTime
        let updatedGeometry = DetailedTimelineGeometry(
            viewportWidth: viewportWidth,
            duration: duration,
            zoomLevel: zoomLevel
        )
        timelineWidth = updatedGeometry.timelineWidth
        contentOffsetX = updatedGeometry.contentOffset(for: preservedTime)
    }

    private func isMultiple(_ value: Double, of interval: Double) -> Bool {
        guard interval > 0 else { return false }
        let remainder = value.truncatingRemainder(dividingBy: interval)
        return abs(remainder) < 0.0001 || abs(remainder - interval) < 0.0001
    }

    private func tickValues(step: Double) -> [Double] {
        guard step > 0 else { return [0] }
        var ticks: [Double] = [0]
        var value = step
        while value < duration {
            ticks.append(value)
            value += step
        }
        if ticks.last != duration {
            ticks.append(duration)
        }
        return ticks
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
