import SwiftUI

public struct GlassSearchField: View {
    @Binding private var text: String
    private let placeholder: String
    private let accessibilityIdentifier: String

    @State private var pressFeedbackTrigger = 0
    @State private var isInputActive = false
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "Search",
        accessibilityIdentifier: String = "DesignSystem-input-search"
    ) {
        _text = text
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.tertiary)

            TextField(
                placeholder,
                text: $text,
                onEditingChanged: handleEditingChanged,
                onCommit: deactivateInput
            )
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.secondary)
            .focused($isFocused)
            .enchronLiteralTextInput()
            .enchronHoverEffectDisabled()
            .onTapGesture(perform: activateInput)
            .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: DesignTokens.Card.gridMin, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .background(DesignTokens.Surface.elevated, in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .contentShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Surface.focusBorder.opacity(isInputActive ? 1 : 0),
                    lineWidth: DesignTokens.Stroke.bold
                )
                .animation(DesignTokens.AnimationToken.selection, value: isInputActive)
        }
        .simultaneousGesture(TapGesture().onEnded(activateInput))
        .enchronPressSensoryFeedback(.button, trigger: pressFeedbackTrigger)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                setInputActive(false)
            }
        }
        .onSubmit(deactivateInput)
        .accessibilityLabel(placeholder)
    }

    private func activateInput() {
        if !isInputActive {
            pressFeedbackTrigger += 1
        }
        setInputActive(true)
        isFocused = true
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        if isEditing {
            setInputActive(true)
        } else {
            deactivateInput()
        }
    }

    private func deactivateInput() {
        setInputActive(false)
        isFocused = false
    }

    private func setInputActive(_ active: Bool) {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isInputActive = active
        }
    }
}

public struct GlassToggle: View {
    @State var isOn: Bool

    public init(isOn: Bool) {
        self.isOn = isOn
    }

    public var body: some View {
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? DesignTokens.Theme.accent : DesignTokens.Surface.elevated)
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
        .enchronHoverContentShape(
            Capsule(),
            insets: EdgeInsets(
                top: (DesignTokens.Interactive.large - 30) / 2,
                leading: (DesignTokens.Interactive.large - 50) / 2,
                bottom: (DesignTokens.Interactive.large - 30) / 2,
                trailing: (DesignTokens.Interactive.large - 50) / 2
            )
        )
    }
}

struct BoundGlassToggle: View {
    @Binding var isOn: Bool
    var isEnabled = true

    init(isOn: Binding<Bool>, isEnabled: Bool = true) {
        _isOn = isOn
        self.isEnabled = isEnabled
    }

    var body: some View {
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? DesignTokens.Theme.accent : DesignTokens.Surface.elevated)
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .clipShape(Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic, isEnabled: isEnabled)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
        .enchronHoverContentShape(
            Capsule(),
            insets: EdgeInsets(
                top: (DesignTokens.Interactive.large - 30) / 2,
                leading: (DesignTokens.Interactive.large - 50) / 2,
                bottom: (DesignTokens.Interactive.large - 30) / 2,
                trailing: (DesignTokens.Interactive.large - 50) / 2
            )
        )
    }
}

private extension VerticalAlignment {
    enum TrackCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let trackCenter = VerticalAlignment(TrackCenterID.self)
}

public struct GlassSliderRail: View {
    let trackWidth: CGFloat
    let trackHeight: CGFloat
    let knobSize: CGFloat
    let knobOffsetX: CGFloat
    let litCenterX: CGFloat
    let litWidth: CGFloat
    let litVisible: Bool
    let isDragging: Bool

    public init(
        trackWidth: CGFloat,
        trackHeight: CGFloat,
        knobSize: CGFloat,
        knobOffsetX: CGFloat,
        litCenterX: CGFloat,
        litWidth: CGFloat,
        litVisible: Bool,
        isDragging: Bool
    ) {
        self.trackWidth = trackWidth
        self.trackHeight = trackHeight
        self.knobSize = knobSize
        self.knobOffsetX = knobOffsetX
        self.litCenterX = litCenterX
        self.litWidth = litWidth
        self.litVisible = litVisible
        self.isDragging = isDragging
    }

    public var body: some View {
        Capsule()
            .fill(DesignTokens.Surface.elevated)
            .frame(width: trackWidth, height: trackHeight)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: max(litWidth, 0), height: trackHeight)
                    .offset(x: litCenterX)
                    .opacity(litVisible ? 1 : 0)
            }
            .overlay(alignment: .center) {
                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(isDragging ? DesignTokens.PressFeedback.control.pressedScale : 1.0)
                    .offset(x: knobOffsetX)
            }
            .clipShape(Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.highlight)
    }
}

public struct CenterSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = -5...5
    let leadingSystemImage: String
    let trailingSystemImage: String
    var accessibilityLabel: String = "Center slider"
    var accessibilityIdentifier: String = "DesignSystem-CenterSlider"
    var trackWidth: CGFloat = 450
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var dragStartValue: Int?
    @State private var isDragging = false
    @State private var pressTrigger = 0
    @State private var releaseTrigger = 0

    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26
    private let dotSize: CGFloat = 4
    private let iconColumnWidth: CGFloat = DesignTokens.Interactive.compact

    private var detentCount: Int { range.count }
    private var midValue: Double { Double(range.lowerBound + range.upperBound) / 2 }
    private var travel: CGFloat { trackWidth - knobSize }
    private var spacing: CGFloat { travel / CGFloat(detentCount - 1) }

    private func offset(for detent: Double) -> CGFloat {
        CGFloat(detent - midValue) * spacing
    }

    private var knobOffset: CGFloat {
        offset(for: Double(value))
    }

    public init(
        value: Binding<Int>,
        range: ClosedRange<Int> = -5...5,
        leadingSystemImage: String,
        trailingSystemImage: String,
        accessibilityLabel: String = "Center slider",
        accessibilityIdentifier: String = "DesignSystem-CenterSlider",
        trackWidth: CGFloat = 450,
        onDraggingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.range = range
        self.leadingSystemImage = leadingSystemImage
        self.trailingSystemImage = trailingSystemImage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trackWidth = trackWidth
        self.onDraggingChanged = onDraggingChanged
    }

    public var body: some View {
        HStack(alignment: .trackCenter, spacing: DesignTokens.Spacing.md) {
            Image(systemName: leadingSystemImage)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .frame(width: iconColumnWidth, height: iconColumnWidth)

            VStack(spacing: DesignTokens.Spacing.sm) {
                track
                    .alignmentGuide(.trackCenter) { $0[VerticalAlignment.center] }
                detentDots
            }

            Image(systemName: trailingSystemImage)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .frame(width: iconColumnWidth, height: iconColumnWidth)
        }
        .accessibilityElement()
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + 1)
            case .decrement: setValue(value - 1)
            @unknown default: break
            }
        }
        .enchronPressSensoryFeedback(.slider, trigger: pressTrigger)
        .enchronPressSensoryFeedback(.sliderRelease, trigger: releaseTrigger)
        .enchronDetentSensoryFeedback(
            value: value,
            lowerBound: range.lowerBound,
            upperBound: range.upperBound
        )
    }

    private var track: some View {
        let radius = trackHeight / 2
        return GlassSliderRail(
            trackWidth: trackWidth,
            trackHeight: trackHeight,
            knobSize: knobSize,
            knobOffsetX: knobOffset,
            litCenterX: (knobOffset + (knobOffset >= 0 ? radius : -radius)) / 2,
            litWidth: abs(knobOffset) + radius,
            litVisible: abs(knobOffset) > 0.5,
            isDragging: isDragging
        )
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                let start = dragStartValue ?? value
                if dragStartValue == nil {
                    dragStartValue = start
                    pressTrigger += 1
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDragging = true
                    }
                    onDraggingChanged(true)
                }
                let landed = offset(for: Double(start)) + gesture.translation.width
                let proposed = clamp(Int((midValue + Double(landed / spacing)).rounded()))
                if proposed != value {
                    withAnimation(snapAnimation(to: proposed)) {
                        value = proposed
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

    private var detentDots: some View {
        ZStack {
            ForEach(Array(range), id: \.self) { detent in
                let isCenter = Double(detent) == midValue
                Circle()
                    .fill(DesignTokens.Surface.divider)
                    .frame(
                        width: isCenter ? dotSize + 3 : dotSize,
                        height: isCenter ? dotSize + 3 : dotSize
                    )
                    .offset(x: offset(for: Double(detent)))
            }
        }
        .frame(width: trackWidth, height: dotSize + 3)
    }

    private func clamp(_ newValue: Int) -> Int {
        min(max(newValue, range.lowerBound), range.upperBound)
    }

    private func snapAnimation(to detent: Int) -> Animation {
        detent == range.lowerBound || detent == range.upperBound
            ? DesignTokens.AnimationToken.sceneCarouselSettle
            : DesignTokens.AnimationToken.selection
    }

    private func setValue(_ newValue: Int) {
        let clamped = clamp(newValue)
        withAnimation(snapAnimation(to: clamped)) {
            value = clamped
        }
    }
}

public struct RangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: String = "Range slider"
    var accessibilityValue: String = ""
    var accessibilityIdentifier: String = "DesignSystem-RangeSlider"
    var trackWidth: CGFloat = 450
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @State private var pressTrigger = 0
    @State private var releaseTrigger = 0

    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26

    private var span: Double {
        let width = range.upperBound - range.lowerBound
        return width > 0 ? width : 1
    }

    private var normalized: CGFloat {
        CGFloat((value - range.lowerBound) / span)
    }

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        accessibilityLabel: String = "Range slider",
        accessibilityValue: String = "",
        accessibilityIdentifier: String = "DesignSystem-RangeSlider",
        trackWidth: CGFloat = 450,
        onDraggingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.range = range
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trackWidth = trackWidth
        self.onDraggingChanged = onDraggingChanged
    }

    public var body: some View {
        let travel = trackWidth - knobSize
        let knobOffsetX = -travel / 2 + normalized * travel
        let radius = trackHeight / 2
        let leftEdge = -trackWidth / 2
        let rightEdge = knobOffsetX + radius
        let litWidth = rightEdge - leftEdge
        let litCenterX = (leftEdge + rightEdge) / 2

        return GlassSliderRail(
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
        .accessibilityElement()
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            let step = span / 100
            switch direction {
            case .increment: value = clamp(value + step)
            case .decrement: value = clamp(value - step)
            @unknown default: break
            }
        }
        .enchronPressSensoryFeedback(.slider, trigger: pressTrigger)
        .enchronPressSensoryFeedback(.sliderRelease, trigger: releaseTrigger)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    pressTrigger += 1
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDragging = true
                    }
                    onDraggingChanged(true)
                }
                let travel = max(trackWidth - knobSize, 1)
                let localX = gesture.location.x - knobSize / 2
                let proposed = min(max(localX / travel, 0), 1)
                value = range.lowerBound + Double(proposed) * span
            }
            .onEnded { _ in
                releaseTrigger += 1
                withAnimation(DesignTokens.PressFeedback.control.releaseAnimation) {
                    isDragging = false
                }
                onDraggingChanged(false)
            }
    }

    private func clamp(_ newValue: Double) -> Double {
        min(max(newValue, range.lowerBound), range.upperBound)
    }
}

public extension View {
    func enchronDetentSensoryFeedback<Value: Comparable & Equatable>(
        value: Value,
        lowerBound: Value,
        upperBound: Value
    ) -> some View {
        modifier(
            DetentedSliderTickSensoryModifier(
                value: value,
                lowerBound: lowerBound,
                upperBound: upperBound
            )
        )
    }
}

private struct DetentedSliderTickSensoryModifier<Value: Comparable & Equatable>: ViewModifier {
    let value: Value
    let lowerBound: Value
    let upperBound: Value

    @ViewBuilder
    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: value) { old, new in
            if new == old { return nil }
            if new == lowerBound { return .selection(.minimum) }
            if new == upperBound { return .selection(.maximum) }
            return new > old ? .increase : .decrease
        }
    }
}
