import DesignSystem
import Foundation
import SwiftUI

public struct DeckMenuItem: Identifiable, Equatable {
    public let id: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(id: String, title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public static func == (lhs: DeckMenuItem, rhs: DeckMenuItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.isSelected == rhs.isSelected
    }
}
enum PrecisionTimelineZoomScale {
    static var availableTimelineWidth: CGFloat {
        DesignTokens.Layout.expandedPlayerControlsContentWidth
    }

    static func minimumPixelsPerSecond(duration: Double) -> CGFloat {
        guard duration > 0 else {
            return DesignTokens.PrecisionTimeline.minPixelsPerSecond
        }
        let fitToViewport = availableTimelineWidth / CGFloat(duration)
        return max(DesignTokens.PrecisionTimeline.minPixelsPerSecond, fitToViewport)
    }

    static func clamped(_ value: CGFloat, duration: Double) -> CGFloat {
        min(
            max(value, minimumPixelsPerSecond(duration: duration)),
            DesignTokens.PrecisionTimeline.maxPixelsPerSecond
        )
    }

    static func normalized(_ pixelsPerSecond: CGFloat, duration: Double) -> CGFloat {
        let minValue = log(Double(minimumPixelsPerSecond(duration: duration)))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let current = log(Double(clamped(pixelsPerSecond, duration: duration)))
        guard maxValue > minValue else { return 0 }
        return CGFloat(min(max((current - minValue) / (maxValue - minValue), 0), 1))
    }

    static func pixelsPerSecond(forNormalized normalized: CGFloat, duration: Double) -> CGFloat {
        let minValue = log(Double(minimumPixelsPerSecond(duration: duration)))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let value = minValue + (maxValue - minValue) * Double(normalized)
        return clamped(CGFloat(exp(value)), duration: duration)
    }
}

struct PrecisionTimelineZoomSlider: View {
    @Binding var pixelsPerSecond: CGFloat
    let duration: Double
    let trackWidth: CGFloat

    static func railWidth(fitting componentWidth: CGFloat) -> CGFloat {
        max(componentWidth - (DesignTokens.Spacing.xl + DesignTokens.Spacing.sm) * 2, 0)
    }

    @State private var isDraggingZoom = false
    @State private var zoomPressTrigger = 0
    @State private var zoomReleaseTrigger = 0
    @State private var zoomBoundary: EnchronScrubBoundary = .none

    private var zoomTrackWidth: CGFloat { trackWidth }
    private var zoomTrackHeight: CGFloat { DesignTokens.PrecisionTimeline.zoomRailHeight }
    private var zoomKnobSize: CGFloat { DesignTokens.PrecisionTimeline.zoomRailThumbSize }

    private var normalizedZoom: CGFloat {
        PrecisionTimelineZoomScale.normalized(pixelsPerSecond, duration: duration)
    }

    var body: some View {
        let travel = zoomTrackWidth - zoomKnobSize
        let normalized = normalizedZoom
        let knobOffsetX = -travel / 2 + normalized * travel
        let radius = zoomTrackHeight / 2
        let leftEdge = -zoomTrackWidth / 2
        let rightEdge = knobOffsetX + radius
        let litWidth = rightEdge - leftEdge
        let litCenterX = (leftEdge + rightEdge) / 2

        return HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.Spacing.xl)
                .accessibilityHidden(true)

            GlassSliderRail(
                trackWidth: zoomTrackWidth,
                trackHeight: zoomTrackHeight,
                knobSize: zoomKnobSize,
                knobOffsetX: knobOffsetX,
                litCenterX: litCenterX,
                litWidth: litWidth,
                litVisible: normalized > 0.001,
                isDragging: isDraggingZoom
            )
            .frame(width: zoomTrackWidth, height: zoomTrackHeight)
            .gesture(zoomSliderGesture)

            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.Spacing.xl)
                .accessibilityHidden(true)
        }
        .font(.body)
        .frame(height: DesignTokens.Interactive.large)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DesignSystem-PrecisionTimeline-zoom")
        .accessibilityLabel("Timeline zoom")
        .accessibilityValue("\(Int(normalized * 100))%")
        .enchronScrubSensoryFeedback(
            pressTrigger: zoomPressTrigger,
            releaseTrigger: zoomReleaseTrigger,
            boundary: zoomBoundary,
            boundariesEnabled: isDraggingZoom
        )
        .onAppear(perform: syncZoomBoundary)
        .onChange(of: pixelsPerSecond) { _, _ in
            if !isDraggingZoom {
                syncZoomBoundary()
            }
        }
    }

    private var zoomSliderGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDraggingZoom {
                    syncZoomBoundary()
                    zoomPressTrigger += 1
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDraggingZoom = true
                    }
                }
                let travel = max(zoomTrackWidth - zoomKnobSize, 1)
                let localX = value.location.x - zoomKnobSize / 2
                let normalized = min(max(localX / travel, 0), 1)
                pixelsPerSecond = PrecisionTimelineZoomScale.pixelsPerSecond(
                    forNormalized: normalized,
                    duration: duration
                )
                zoomBoundary = EnchronScrubBoundary.from(normalized: Double(normalized))
            }
            .onEnded { _ in
                zoomReleaseTrigger += 1
                withAnimation(DesignTokens.PressFeedback.control.releaseAnimation) {
                    isDraggingZoom = false
                }
            }
    }

    private func syncZoomBoundary() {
        zoomBoundary = EnchronScrubBoundary.from(normalized: Double(normalizedZoom))
    }
}

struct PrecisionTimelineView: View {
    @Binding var currentTime: Double
    @Binding var pixelsPerSecond: CGFloat

    let duration: Double
    let framesPerSecond: Double
    var onSeekBegan: () -> Void = {}
    var onSeekEnded: (Double) -> Void = { _ in }

    @GestureState private var gestureStartPixelsPerSecond: CGFloat?
    @State private var isDraggingTimeline = false
    @State private var dragStartTime: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = max(proxy.size.width, 1)
            let safePixelsPerSecond = clampedPixelsPerSecond(pixelsPerSecond)
            let leadingX = viewportWidth / 2 - CGFloat(currentTime) * safePixelsPerSecond
            let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.element, style: .continuous)

            ZStack(alignment: .topLeading) {
                shape
                    .fill(.ultraThickMaterial)

                timelineRuler(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: safePixelsPerSecond
                )
                .frame(height: DesignTokens.PrecisionTimeline.rulerHeight)

                filmStrip(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: safePixelsPerSecond,
                    height: max(proxy.size.height - DesignTokens.PrecisionTimeline.rulerHeight, 1)
                )
                .offset(y: DesignTokens.PrecisionTimeline.rulerHeight)

                playhead(
                    x: viewportWidth / 2,
                    height: proxy.size.height
                )
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    DesignTokens.Surface.divider,
                    lineWidth: DesignTokens.Stroke.subtle
                )
            }
            .overlay(alignment: .top) {
                timecodeLabel
                    .padding(.top, DesignTokens.Spacing.xs)
            }
            .enchronHoverContentShape(shape)
            .enchronHoverEffect(.automatic)
            .contentShape(shape)
            .gesture(timelineDragGesture(pixelsPerSecond: safePixelsPerSecond))
        }
        .gesture(zoomGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-precision-timeline")
        .accessibilityLabel("Precision timeline")
    }

    private var timecodeLabel: some View {
        Text(PrecisionTimelineFormatter.timecode(currentTime, framesPerSecond: framesPerSecond))
            .font(DesignTokens.Typography.metadata)
            .monospacedDigit()
            .foregroundStyle(DesignTokens.PrecisionTimeline.timecodeColor)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(
                .thickMaterial,
                in: RoundedRectangle(
                    cornerRadius: DesignTokens.ProgressBar.timeBubbleRadius,
                    style: .continuous
                )
            )
            .allowsHitTesting(false)
            .accessibilityIdentifier("DesignSystem-PrecisionTimeline-timecode")
    }

    private func timelineRuler(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> some View {
        Canvas { context, size in
            let intervals = tickIntervals(pixelsPerSecond: pixelsPerSecond)
            drawTicks(
                context: &context,
                size: size,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond,
                interval: intervals.minor,
                height: DesignTokens.PrecisionTimeline.minorTickHeight,
                color: DesignTokens.PrecisionTimeline.minorTickColor,
                lineWidth: DesignTokens.Stroke.subtle
            )
            drawTicks(
                context: &context,
                size: size,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond,
                interval: intervals.major,
                height: DesignTokens.PrecisionTimeline.majorTickHeight,
                color: DesignTokens.PrecisionTimeline.majorTickColor,
                lineWidth: DesignTokens.Stroke.regular
            )
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(visibleTickTimes(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: pixelsPerSecond,
                    interval: tickIntervals(pixelsPerSecond: pixelsPerSecond).major
                ), id: \.self) { time in
                    Text(PrecisionTimelineFormatter.clock(time))
                        .font(DesignTokens.Typography.monospacedDetail)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.PrecisionTimeline.secondaryTextColor)
                        .position(
                            x: leadingX + CGFloat(time) * pixelsPerSecond,
                            y: DesignTokens.Spacing.sm
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func filmStrip(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        height: CGFloat
    ) -> some View {
        Canvas { context, size in
            drawFilmStrip(
                context: &context,
                size: size,
                viewportWidth: viewportWidth,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond
            )
        }
        .frame(height: height)
    }

    private func playhead(x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(DesignTokens.PrecisionTimeline.playheadColor)
            .frame(width: DesignTokens.PrecisionTimeline.playheadWidth)
            .frame(height: height)
            .shadow(
                color: DesignTokens.PrecisionTimeline.playheadShadow,
                radius: DesignTokens.PrecisionTimeline.playheadShadowRadius,
                x: DesignTokens.PrecisionTimeline.playheadShadowOffsetX
            )
            .position(
                x: x,
                y: height / 2
            )
            .allowsHitTesting(false)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureStartPixelsPerSecond) { _, state, _ in
                if state == nil {
                    state = pixelsPerSecond
                }
            }
            .onChanged { value in
                let start = gestureStartPixelsPerSecond ?? pixelsPerSecond
                pixelsPerSecond = clampedPixelsPerSecond(start * value.magnification)
            }
    }

    private func timelineDragGesture(pixelsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                if !isDraggingTimeline {
                    isDraggingTimeline = true
                    dragStartTime = currentTime
                    onSeekBegan()
                }

                let delta = Double(value.translation.width / pixelsPerSecond)
                let targetTime = dragStartTime - delta
                currentTime = quantizedIfNeeded(clampedTime(targetTime))
            }
            .onEnded { _ in
                isDraggingTimeline = false
                onSeekEnded(currentTime)
            }
    }

    private func drawTicks(
        context: inout GraphicsContext,
        size: CGSize,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        interval: Double,
        height: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        guard interval > 0, duration > 0 else { return }

        let visibleTimes = visibleTickTimes(
            viewportWidth: size.width,
            leadingX: leadingX,
            pixelsPerSecond: pixelsPerSecond,
            interval: interval
        )
        let centerY = size.height - DesignTokens.Spacing.xs

        for time in visibleTimes {
            let x = leadingX + CGFloat(time) * pixelsPerSecond
            var path = Path()
            path.move(to: CGPoint(x: x, y: centerY - height))
            path.addLine(to: CGPoint(x: x, y: centerY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func drawFilmStrip(
        context: inout GraphicsContext,
        size: CGSize,
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat
    ) {
        guard duration > 0 else { return }

        let contentWidth = CGFloat(duration) * pixelsPerSecond
        let segmentWidth = max(
            DesignTokens.PrecisionTimeline.thumbnailMinWidth,
            pixelsPerSecond * DesignTokens.PrecisionTimeline.thumbnailSecondsScale
        )
        let visibleStart = max(-leadingX, 0)
        let visibleEnd = min(viewportWidth - leadingX, contentWidth)
        guard visibleStart < visibleEnd else { return }

        let visibleFilmRect = CGRect(
            x: leadingX + visibleStart,
            y: 0,
            width: visibleEnd - visibleStart,
            height: size.height
        )
        context.fill(
            Path(visibleFilmRect),
            with: .color(DesignTokens.PrecisionTimeline.filmStripBase)
        )
        let bandHeight = min(DesignTokens.PrecisionTimeline.filmImageInset, size.height / 2)
        context.fill(
            Path(CGRect(
                x: visibleFilmRect.minX,
                y: visibleFilmRect.minY,
                width: visibleFilmRect.width,
                height: bandHeight
            )),
            with: .color(DesignTokens.PrecisionTimeline.filmStripBand)
        )
        context.fill(
            Path(CGRect(
                x: visibleFilmRect.minX,
                y: visibleFilmRect.maxY - bandHeight,
                width: visibleFilmRect.width,
                height: bandHeight
            )),
            with: .color(DesignTokens.PrecisionTimeline.filmStripBand)
        )

        let fullCount = Int(floor(contentWidth / segmentWidth))
        let remainder = contentWidth - CGFloat(fullCount) * segmentWidth
        let lastDrawIndex = (remainder >= segmentWidth * 0.5) ? fullCount : max(fullCount - 1, 0)

        let startIndex = max(Int(floor(visibleStart / segmentWidth)), 0)
        let endIndex = min(max(Int(ceil(visibleEnd / segmentWidth)), startIndex), lastDrawIndex)
        guard startIndex <= endIndex else { return }

        var stripContext = context
        stripContext.clip(to: Path(visibleFilmRect))

        for index in startIndex...endIndex {
            let leftContentX = CGFloat(index) * segmentWidth
            let rightContentX = (index == lastDrawIndex)
                ? contentWidth
                : CGFloat(index + 1) * segmentWidth
            let rect = CGRect(
                x: leadingX + leftContentX,
                y: DesignTokens.PrecisionTimeline.filmImageInset,
                width: max(rightContentX - leftContentX, 1),
                height: max(size.height - DesignTokens.PrecisionTimeline.filmImageInset * 2, 1)
            )
            let palette = DesignTokens.PrecisionTimeline.thumbnailPalette
            let color = palette[index % palette.count]
            let path = Path(rect.insetBy(dx: DesignTokens.Stroke.regular, dy: DesignTokens.Stroke.subtle))

            stripContext.fill(path, with: .color(color))
            stripContext.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.minY + DesignTokens.Stroke.regular,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.34
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripHighlight)
            )
            stripContext.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.midY,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.5
                )),
                with: .color(Color.black.opacity(0.12))
            )
            stripContext.fill(
                Path(CGRect(
                    x: rect.maxX - DesignTokens.PrecisionTimeline.thumbnailSeparatorWidth,
                    y: rect.minY,
                    width: DesignTokens.PrecisionTimeline.thumbnailSeparatorWidth,
                    height: rect.height
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripSeparator)
            )
        }

        drawSprockets(
            context: &context,
            size: size,
            leadingX: leadingX,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd
        )
    }

    private func drawSprockets(
        context: inout GraphicsContext,
        size: CGSize,
        leadingX: CGFloat,
        visibleStart: CGFloat,
        visibleEnd: CGFloat
    ) {
        let holeWidth = DesignTokens.PrecisionTimeline.sprocketWidth
        let holeHeight = DesignTokens.PrecisionTimeline.sprocketHeight
        let step = holeWidth + DesignTokens.PrecisionTimeline.sprocketSpacing
        guard step > 0 else { return }

        let startIndex = max(Int(ceil(visibleStart / step)), 0)
        let endIndex = Int(floor((visibleEnd - holeWidth) / step))
        guard startIndex <= endIndex else { return }
        let topY = DesignTokens.Spacing.xxs
        let bottomY = size.height - holeHeight - DesignTokens.Spacing.xxs

        for index in startIndex...endIndex {
            let x = leadingX + CGFloat(index) * step
            let topRect = CGRect(x: x, y: topY, width: holeWidth, height: holeHeight)
            let bottomRect = CGRect(x: x, y: bottomY, width: holeWidth, height: holeHeight)
            let topPath = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .path(in: topRect)
            let bottomPath = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .path(in: bottomRect)

            context.fill(topPath, with: .color(DesignTokens.PrecisionTimeline.sprocketFill))
            context.fill(bottomPath, with: .color(DesignTokens.PrecisionTimeline.sprocketFill))
        }
    }

    private func visibleTickTimes(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        interval: Double
    ) -> [Double] {
        guard interval > 0, pixelsPerSecond > 0 else { return [] }

        let startTime = max(0, Double((-leadingX - DesignTokens.Spacing.lg) / pixelsPerSecond))
        let endTime = min(
            duration,
            Double((viewportWidth - leadingX + DesignTokens.Spacing.lg) / pixelsPerSecond)
        )
        guard startTime <= endTime else { return [] }

        let firstTick = floor(startTime / interval) * interval
        let tickCount = Int(ceil((endTime - firstTick) / interval))

        return (0...max(tickCount, 0))
            .map { firstTick + Double($0) * interval }
            .filter { $0 >= 0 && $0 <= duration }
    }

    private func tickIntervals(pixelsPerSecond: CGFloat) -> (minor: Double, major: Double) {
        let secondsPerPoint = 1 / Double(max(pixelsPerSecond, 0.001))
        let frameInterval = 1 / max(framesPerSecond, 1)
        let intervals = niceIntervals(frameInterval: frameInterval)
        let minorTarget = secondsPerPoint * Double(DesignTokens.PrecisionTimeline.minorTickTargetSpacing)
        let majorTarget = secondsPerPoint * Double(DesignTokens.PrecisionTimeline.majorTickTargetSpacing)
        let minor = intervals.first { $0 >= minorTarget } ?? max(minorTarget, frameInterval)
        let major = intervals.first { $0 >= max(majorTarget, minor * 2) } ?? max(majorTarget, minor * 2)

        return (minor, major)
    }

    private func niceIntervals(frameInterval: Double) -> [Double] {
        [
            frameInterval,
            frameInterval * 2,
            frameInterval * 4,
            0.25,
            0.5,
            1,
            2,
            5,
            10,
            15,
            30,
            60,
            120,
            300,
            600,
            1_200,
            1_800,
            3_600
        ]
    }

    private var frameDuration: Double {
        1 / max(framesPerSecond, 1)
    }

    private func quantizedIfNeeded(_ time: Double) -> Double {
        let pointsPerFrame = clampedPixelsPerSecond(pixelsPerSecond) * CGFloat(frameDuration)
        guard pointsPerFrame >= DesignTokens.Spacing.xs else { return time }
        return (time / frameDuration).rounded() * frameDuration
    }

    private func clampedTime(_ time: Double) -> Double {
        min(max(time, 0), duration)
    }

    private func clampedPixelsPerSecond(_ value: CGFloat) -> CGFloat {
        PrecisionTimelineZoomScale.clamped(value, duration: duration)
    }
}

private enum PrecisionTimelineFormatter {
    static func clock(_ seconds: Double) -> String {
        let clamped = max(seconds, 0)
        let totalSeconds = Int(clamped.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func timecode(_ seconds: Double, framesPerSecond: Double) -> String {
        let frameRate = max(Int(framesPerSecond.rounded()), 1)
        let totalFrames = max(Int((seconds * Double(frameRate)).rounded()), 0)
        let framesPerHour = frameRate * 3_600
        let framesPerMinute = frameRate * 60
        let hours = totalFrames / framesPerHour
        let minutes = (totalFrames % framesPerHour) / framesPerMinute
        let secs = (totalFrames % framesPerMinute) / frameRate
        let frame = totalFrames % frameRate

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frame)
    }
}
