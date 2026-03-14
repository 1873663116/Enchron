import CoreGraphics
import Foundation

struct DetailedTimelineGeometry: Sendable {
    private static let niceIntervals: [Double] = [
        0.25, 0.5, 1, 2, 5, 10, 15, 30,
        60, 90, 120, 300, 600, 900, 1800, 3600
    ]

    let viewportWidth: CGFloat
    let duration: Double
    let timelineWidth: CGFloat
    let minimumWidthFactor: CGFloat
    let maximumWidthFactor: CGFloat

    init(
        viewportWidth: CGFloat,
        duration: Double,
        timelineWidth: CGFloat,
        minimumWidthFactor: CGFloat = 0.5,
        maximumWidthFactor: CGFloat = 4.0
    ) {
        self.viewportWidth = max(viewportWidth, 1)
        self.duration = max(duration, 0.1)
        self.minimumWidthFactor = minimumWidthFactor
        self.maximumWidthFactor = max(maximumWidthFactor, minimumWidthFactor)
        self.timelineWidth = Self.clampedWidth(
            timelineWidth,
            viewportWidth: self.viewportWidth,
            minimumWidthFactor: minimumWidthFactor,
            maximumWidthFactor: self.maximumWidthFactor
        )
    }

    init(
        viewportWidth: CGFloat,
        duration: Double,
        zoomLevel: Double,
        minimumWidthFactor: CGFloat = 0.5,
        maximumWidthFactor: CGFloat = 4.0
    ) {
        let safeViewport = max(viewportWidth, 1)
        let minWidth = safeViewport * minimumWidthFactor
        let maxWidth = safeViewport * max(maximumWidthFactor, minimumWidthFactor)
        let clampedZoom = min(max(zoomLevel, 0), 1)
        let resolvedWidth = minWidth + (maxWidth - minWidth) * CGFloat(clampedZoom)

        self.init(
            viewportWidth: safeViewport,
            duration: duration,
            timelineWidth: resolvedWidth,
            minimumWidthFactor: minimumWidthFactor,
            maximumWidthFactor: maximumWidthFactor
        )
    }

    var minimumTimelineWidth: CGFloat {
        viewportWidth * minimumWidthFactor
    }

    var maximumTimelineWidth: CGFloat {
        viewportWidth * maximumWidthFactor
    }

    func zoomLevel(for timelineWidth: CGFloat) -> Double {
        let span = max(maximumTimelineWidth - minimumTimelineWidth, 1)
        return Double((clampedTimelineWidth(timelineWidth) - minimumTimelineWidth) / span)
    }

    func clampedTimelineWidth(_ width: CGFloat) -> CGFloat {
        Self.clampedWidth(
            width,
            viewportWidth: viewportWidth,
            minimumWidthFactor: minimumWidthFactor,
            maximumWidthFactor: maximumWidthFactor
        )
    }

    var secondsPerPoint: Double {
        duration / Double(max(timelineWidth, 1))
    }

    var centerAxisX: CGFloat {
        viewportWidth / 2
    }

    var minimumContentOffset: CGFloat {
        -timelineWidth / 2
    }

    var maximumContentOffset: CGFloat {
        timelineWidth / 2
    }

    func clampedContentOffset(_ offset: CGFloat) -> CGFloat {
        max(minimumContentOffset, min(maximumContentOffset, offset))
    }

    func contentOffset(for time: Double) -> CGFloat {
        let clampedTime = max(0, min(duration, time))
        let pointOnTimeline = CGFloat(clampedTime / secondsPerPoint)
        return clampedContentOffset((timelineWidth / 2) - pointOnTimeline)
    }

    func time(atContentOffset offset: CGFloat) -> Double {
        let pointOnTimeline = timelineWidth / 2 - clampedContentOffset(offset)
        return max(0, min(duration, Double(pointOnTimeline) * secondsPerPoint))
    }

    func xPosition(for time: Double) -> CGFloat {
        let clampedTime = max(0, min(duration, time))
        return CGFloat(clampedTime / secondsPerPoint)
    }

    func timelineBodyLeadingX(for contentOffset: CGFloat) -> CGFloat {
        centerAxisX - (timelineWidth / 2) + clampedContentOffset(contentOffset)
    }

    func tickIntervals(minorSpacing: CGFloat = 18, majorSpacing: CGFloat = 88) -> (minor: Double, major: Double) {
        let minorInterval = niceInterval(for: secondsPerPoint * Double(max(minorSpacing, 1)))
        let majorTarget = max(
            secondsPerPoint * Double(max(majorSpacing, 1)),
            minorInterval * 2
        )
        let majorInterval = Self.niceIntervals.first {
            $0 >= majorTarget && isMultiple($0, of: minorInterval)
        } ?? (minorInterval * 10)

        return (minorInterval, majorInterval)
    }

    func tickInterval(targetSpacing: CGFloat = 80) -> Double {
        tickIntervals(majorSpacing: targetSpacing).major
    }

    private func niceInterval(for rawInterval: Double) -> Double {
        Self.niceIntervals.first { $0 >= rawInterval } ?? rawInterval
    }

    private func isMultiple(_ value: Double, of interval: Double) -> Bool {
        guard interval > 0 else { return false }
        let ratio = value / interval
        return abs(ratio.rounded() - ratio) < 0.0001
    }

    private static func clampedWidth(
        _ width: CGFloat,
        viewportWidth: CGFloat,
        minimumWidthFactor: CGFloat,
        maximumWidthFactor: CGFloat
    ) -> CGFloat {
        let minWidth = viewportWidth * minimumWidthFactor
        let maxWidth = viewportWidth * max(maximumWidthFactor, minimumWidthFactor)
        return max(minWidth, min(maxWidth, width))
    }
}

struct DetailedTimelinePreviewSeekPolicy: Sendable {
    let minimumInterval: TimeInterval
    let minimumDelta: Double
    let boundaryTolerance: Double

    init(
        minimumInterval: TimeInterval = 0.125,
        minimumDelta: Double = 0.25,
        boundaryTolerance: Double = 0.001
    ) {
        self.minimumInterval = minimumInterval
        self.minimumDelta = minimumDelta
        self.boundaryTolerance = boundaryTolerance
    }

    func shouldDispatchSeek(
        elapsed: TimeInterval,
        targetTime: Double,
        lastSeekTarget: Double,
        duration: Double
    ) -> Bool {
        let clampedDuration = max(duration, 0)
        let clampedTarget = max(0, min(clampedDuration, targetTime))
        let isAtBoundary =
            clampedTarget <= boundaryTolerance ||
            abs(clampedTarget - clampedDuration) <= boundaryTolerance

        if isAtBoundary {
            return lastSeekTarget < 0 || abs(clampedTarget - lastSeekTarget) > boundaryTolerance
        }

        guard elapsed >= minimumInterval else { return false }
        guard lastSeekTarget < 0 || abs(clampedTarget - lastSeekTarget) >= minimumDelta else {
            return false
        }
        return true
    }
}
