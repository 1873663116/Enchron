import DesignSystem
import SwiftUI

enum PlaybackSurfaceSeekFeedbackGeometry {
    static let width: CGFloat = 320
    static let height = DesignTokens.PrecisionTimeline.rulerHeight * 2
    static let viewportSeconds: Double = 60

    static var pixelsPerSecond: CGFloat {
        (width - DesignTokens.Spacing.md * 2) / CGFloat(viewportSeconds)
    }

    static func position(offsetSeconds: Double, selectedOffsetSeconds: Double) -> CGFloat {
        width / 2 + CGFloat(offsetSeconds - selectedOffsetSeconds) * pixelsPerSecond
    }

    static func ticks(in range: ClosedRange<Double>, interval: Double) -> [Double] {
        let first = ceil(range.lowerBound / interval) * interval
        return stride(from: first, through: range.upperBound, by: interval).map { $0 }
    }

    static func signedOffset(_ seconds: Double) -> String {
        let rounded = Int(abs(seconds).rounded())
        return "\(seconds < 0 ? "−" : "+")\(rounded) S"
    }
}

struct PlaybackSurfaceSeekFeedback: View {
    let preview: PlaybackSurfaceGesturePreview

    private var reachableOffsets: ClosedRange<Double> {
        preview.lowerReachableOffsetSeconds...preview.upperReachableOffsetSeconds
    }

    private var majorTicks: [Double] {
        Array(Set(
            PlaybackSurfaceSeekFeedbackGeometry.ticks(in: reachableOffsets, interval: 10)
                + [preview.lowerReachableOffsetSeconds, preview.upperReachableOffsetSeconds]
        )).sorted()
    }

    private var readout: String {
        PlaybackTimeFormatter.clock(preview.originSeconds)
            + " " + PlaybackSurfaceSeekFeedbackGeometry.signedOffset(preview.offsetSeconds)
    }

    var body: some View {
        let leadingX = PlaybackSurfaceSeekFeedbackGeometry.position(
            offsetSeconds: 0,
            selectedOffsetSeconds: preview.offsetSeconds
        )
        let rulerHeight = DesignTokens.PrecisionTimeline.rulerHeight

        ZStack(alignment: .topLeading) {
            PrecisionTimelineTicks(
                minorTimes: PlaybackSurfaceSeekFeedbackGeometry.ticks(in: reachableOffsets, interval: 5),
                majorTimes: majorTicks,
                leadingX: leadingX,
                pixelsPerSecond: PlaybackSurfaceSeekFeedbackGeometry.pixelsPerSecond
            )
            .frame(height: rulerHeight)
            .offset(y: rulerHeight)

            PrecisionTimelinePlayhead(
                x: PlaybackSurfaceSeekFeedbackGeometry.width / 2,
                height: rulerHeight
            )
            .offset(y: rulerHeight)
        }
        .frame(
            width: PlaybackSurfaceSeekFeedbackGeometry.width,
            height: PlaybackSurfaceSeekFeedbackGeometry.height
        )
        .overlay(alignment: .top) {
            PrecisionTimelineTimeLabel(text: readout)
                .padding(.top, DesignTokens.Spacing.xs)
        }
        .clipShape(PrecisionTimelineGeometry.shape)
        .enchronGlassBackground(in: PrecisionTimelineGeometry.shape)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("PlayerUI-surface-seek-feedback")
        .accessibilityLabel("Seek preview")
        .accessibilityValue(
            readout + "; lowerOffset=\(preview.lowerReachableOffsetSeconds)"
                + "; upperOffset=\(preview.upperReachableOffsetSeconds)"
        )
    }
}
