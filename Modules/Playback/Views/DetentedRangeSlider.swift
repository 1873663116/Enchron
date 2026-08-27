import DesignSystem
import SwiftUI

public struct DetentedRangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var accessibilityLabel: String = "Range slider"
    var accessibilityValue: String = ""
    var accessibilityIdentifier: String = "DesignSystem-DetentedRangeSlider"
    var trackWidth: CGFloat = 450
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var dragStartValue: Double?
    @State private var isDragging = false
    @State private var pressTrigger = 0
    @State private var releaseTrigger = 0

    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26
    private let dotSize: CGFloat = 4

    private var span: Double {
        let width = range.upperBound - range.lowerBound
        return width > 0 ? width : 1
    }

    private var safeStep: Double {
        step > 0 ? step : span
    }

    private var detentCount: Int {
        max(Int((span / safeStep).rounded()) + 1, 2)
    }

    private var travel: CGFloat {
        max(trackWidth - knobSize, 1)
    }

    private var spacing: CGFloat {
        travel / CGFloat(detentCount - 1)
    }

    private var snappedValue: Double {
        nearestDetent(to: value)
    }

    private var normalized: CGFloat {
        CGFloat((snappedValue - range.lowerBound) / span)
    }

    private func offset(forDetentIndex index: Int) -> CGFloat {
        -travel / 2 + CGFloat(index) * spacing
    }

    private func offset(forValue value: Double) -> CGFloat {
        let clamped = clamp(value)
        return -travel / 2 + CGFloat((clamped - range.lowerBound) / span) * travel
    }

    private func detentValue(at index: Int) -> Double {
        let raw = range.lowerBound + Double(index) * safeStep
        return min(raw, range.upperBound)
    }

    private func nearestDetent(to proposed: Double) -> Double {
        let index = ((proposed - range.lowerBound) / safeStep).rounded()
        return clamp(range.lowerBound + index * safeStep)
    }

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        accessibilityLabel: String = "Range slider",
        accessibilityValue: String = "",
        accessibilityIdentifier: String = "DesignSystem-DetentedRangeSlider",
        trackWidth: CGFloat = 450,
        onDraggingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.range = range
        self.step = step
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trackWidth = trackWidth
        self.onDraggingChanged = onDraggingChanged
    }

    public var body: some View {
        let knobOffsetX = offset(forValue: snappedValue)
        let radius = trackHeight / 2
        let leftEdge = -trackWidth / 2
        let rightEdge = knobOffsetX + radius
        let litWidth = rightEdge - leftEdge
        let litCenterX = (leftEdge + rightEdge) / 2

        VStack(spacing: DesignTokens.Spacing.sm) {
            GlassSliderRail(
                trackWidth: trackWidth,
                trackHeight: trackHeight,
                knobSize: knobSize,
                knobOffsetX: knobOffsetX,
                litCenterX: litCenterX,
                litWidth: litWidth,
                litVisible: normalized > 0.001,
                isDragging: isDragging
            )
            .frame(width: trackWidth, height: trackHeight)
            .gesture(dragGesture)

            detentDots
        }
        .accessibilityElement()
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(snappedValue + safeStep)
            case .decrement: setValue(snappedValue - safeStep)
            @unknown default: break
            }
        }
        .enchronPressSensoryFeedback(.slider, trigger: pressTrigger)
        .enchronPressSensoryFeedback(.sliderRelease, trigger: releaseTrigger)
        .enchronDetentSensoryFeedback(
            value: snappedValue,
            lowerBound: range.lowerBound,
            upperBound: range.upperBound
        )
        .onAppear {
            let snapped = nearestDetent(to: value)
            if abs(snapped - value) > safeStep * 0.001 {
                value = snapped
            }
        }
    }

    private var detentDots: some View {
        ZStack {
            ForEach(0..<detentCount, id: \.self) { index in
                Circle()
                    .fill(DesignTokens.Surface.divider)
                    .frame(width: dotSize, height: dotSize)
                    .offset(x: offset(forDetentIndex: index))
            }
        }
        .frame(width: trackWidth, height: dotSize)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let start = dragStartValue ?? snappedValue
                if dragStartValue == nil {
                    dragStartValue = start
                    pressTrigger += 1
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDragging = true
                    }
                    onDraggingChanged(true)
                }
                let landed = offset(forValue: start) + gesture.translation.width
                let normalized = min(max((landed + travel / 2) / travel, 0), 1)
                let proposed = range.lowerBound + Double(normalized) * span
                let snapped = nearestDetent(to: proposed)
                if abs(snapped - value) > safeStep * 0.0001 {
                    withAnimation(snapAnimation(to: snapped)) {
                        value = snapped
                    }
                }
            }
            .onEnded { _ in
                dragStartValue = nil
                releaseTrigger += 1
                withAnimation(DesignTokens.PressFeedback.control.releaseAnimation) {
                    isDragging = false
                }
                onDraggingChanged(false)
            }
    }

    private func snapAnimation(to detent: Double) -> Animation {
        abs(detent - range.lowerBound) < safeStep * 0.001
            || abs(detent - range.upperBound) < safeStep * 0.001
            ? DesignTokens.AnimationToken.sceneCarouselSettle
            : DesignTokens.AnimationToken.selection
    }

    private func setValue(_ newValue: Double) {
        let snapped = nearestDetent(to: newValue)
        withAnimation(snapAnimation(to: snapped)) {
            value = snapped
        }
    }

    private func clamp(_ newValue: Double) -> Double {
        min(max(newValue, range.lowerBound), range.upperBound)
    }
}
