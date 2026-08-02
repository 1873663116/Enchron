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
        accessibilityIdentifier: String = "DesignPreview-input-search"
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
        .enchronGlassBackground(in: Capsule())
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
        .accessibilityIdentifier(accessibilityIdentifier)
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
        .enchronGlassBackground(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

public struct BoundGlassToggle: View {
    @Binding var isOn: Bool
    var isEnabled = true

    public init(isOn: Binding<Bool>, isEnabled: Bool = true) {
        _isOn = isOn
        self.isEnabled = isEnabled
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .clipShape(Capsule())
        .enchronGlassBackground(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic, isEnabled: isEnabled)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

// MARK: - Center slider (centered, detented, bidirectional value track)

/// Keeps the end icons aligned to the *track's* centre while the detent dots
/// hang below it. Without this the enclosing HStack would centre the icons on
/// the track+dots midpoint and they'd sit too low.
private extension VerticalAlignment {
    enum TrackCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let trackCenter = VerticalAlignment(TrackCenterID.self)
}

/// A centered value track: the knob rests at the middle origin and can be
/// dragged to symmetric notches on either side (e.g. exposure −5…+5). It reuses
/// the toggle's white knob + glass capsule vocabulary; the track stays an empty
/// grey capsule (no progress-style fill), with faint detent dots below it and a
/// caller-supplied semantic icon at each end. No numeric readout — the knob
/// position and the end icons carry the meaning. Snap-to-nearest on release.
///
/// Shared glass slider visual used by `CenterSlider` (centre-origin, detented)
/// and the timeline zoom slider (leading-origin, continuous). It draws only the
/// capsule track, accent lit fill, and white knob; the caller computes the
/// knob/lit geometry and attaches the drag gesture, so both sliders render
/// identically. The accent capsule carries its own `glassBackgroundEffect` so
/// the glass rim follows the lit shape rather than reading as flat paint.
public struct GlassSliderRail: View {
    let trackWidth: CGFloat
    let trackHeight: CGFloat
    let knobSize: CGFloat
    /// Knob centre offset from the track's centre.
    let knobOffsetX: CGFloat
    /// Accent lit-fill centre offset from the track's centre.
    let litCenterX: CGFloat
    /// Accent lit-fill width.
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
                    .enchronGlassBackground(in: Capsule())
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
            .enchronGlassBackground(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.highlight)
    }
}

/// `CenterSlider` is the macro component; a `CenterDetentSlider` specialization
/// can be split out later if a non-detented (continuous) variant is needed.
public struct CenterSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = -5...5
    let leadingSystemImage: String
    let trailingSystemImage: String
    var accessibilityLabel: String = "Center slider"
    var accessibilityIdentifier: String = "DesignPreview-CenterSlider"
    var trackWidth: CGFloat = 450
    /// 拖动状态上抛给宿主行:行据此让"标题/数值 readout"在拖动期间保持可见
    /// (gaze hover 在拖动时会离开该行,单靠 hover 会让 readout 消失)。
    var onDraggingChanged: (Bool) -> Void = { _ in }

    // Value at the moment the drag began; the live snap measures the finger's
    // translation against this origin so the knob lands on whole detents only.
    @State private var dragStartValue: Int?
    @State private var isDragging = false
    @State private var pressTrigger = 0
    @State private var releaseTrigger = 0

    // EXPLORATORY: track-bar dimensions are not yet promoted to DesignTokens.
    // Knob (26) and track height (30) mirror the existing toggle for reuse;
    // promoting these to shared tokens needs a separate human decision.
    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26
    private let dotSize: CGFloat = 4
    private let iconColumnWidth: CGFloat = DesignTokens.Interactive.compact

    private var detentCount: Int { range.count }
    private var midValue: Double { Double(range.lowerBound + range.upperBound) / 2 }
    private var travel: CGFloat { trackWidth - knobSize }
    private var spacing: CGFloat { travel / CGFloat(detentCount - 1) }

    /// Horizontal offset (from track centre) of a given detent value.
    private func offset(for detent: Double) -> CGFloat {
        CGFloat(detent - midValue) * spacing
    }

    // The knob is purely a function of the committed detent — it never sits
    // between notches. Live snapping (below) keeps `value` quantised during the
    // drag, so the knob and lit fill can never overshoot past the end value.
    private var knobOffset: CGFloat {
        offset(for: Double(value))
    }

    public init(
        value: Binding<Int>,
        range: ClosedRange<Int> = -5...5,
        leadingSystemImage: String,
        trailingSystemImage: String,
        accessibilityLabel: String = "Center slider",
        accessibilityIdentifier: String = "DesignPreview-CenterSlider",
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

            // Track + dots share a column so the dots get real layout space
            // below the track. A bare `.offset` pushed them outside the bounds
            // and they never composited. The `.trackCenter` guide keeps the end
            // icons aligned to the track's centre, not the column's midpoint.
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
        .modifier(DetentedSliderTickSensoryModifier(
            value: value,
            lowerBound: range.lowerBound,
            upperBound: range.upperBound
        ))
    }

    // Gesture lives on the *static* track, never on the moving knob, so the
    // drag coordinate space stays fixed and the offset can't feed back on itself
    // (the source of the earlier jitter). The accent lit-fill runs from the
    // centre origin to the knob; hidden at the origin. Visual is shared with the
    // timeline zoom slider via `GlassSliderRail`.
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
                // Map the finger's position back to the nearest in-range detent
                // and commit it live; the knob then glides notch-to-notch with the
                // selection spring, reading as a magnetic snap rather than a free
                // slide that has to be caught on release.
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
                // All dots share the empty track's own tint so they read as quiet
                // anchors, never competing with the knob or the lit fill for
                // attention. The centre origin stands out only by its larger
                // size, not by a brighter colour.
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

    // Mid-track snaps keep the bouncy `selection` spring for the magnetic Q feel;
    // snaps onto the two end detents settle without overshoot, so the bounce
    // can't drive the knob past the clipped capsule edge and spring back.
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

/// Leading-origin continuous slider over an arbitrary `Double` range. Shares the
/// `GlassSliderRail` visual (track + accent lit-fill + white knob) and the
/// leading-origin lit-fill geometry with the timeline zoom slider; unlike
/// `CenterSlider` it is not detented and maps a finger position straight onto the
/// value domain. Press feedback and motion all read from `DesignTokens`.
public struct RangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: String = "Range slider"
    var accessibilityValue: String = ""
    var accessibilityIdentifier: String = "DesignPreview-RangeSlider"
    var trackWidth: CGFloat = 450
    /// 拖动状态上抛给宿主行(见 CenterSlider.onDraggingChanged)。
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false
    @State private var pressTrigger = 0
    @State private var releaseTrigger = 0

    // EXPLORATORY: track-bar dimensions are not yet promoted to DesignTokens.
    // Knob (26) and track height (30) mirror CenterSlider so the two read as the
    // same control; promoting these to shared tokens needs a separate human
    // decision (same note as CenterSlider / the zoom slider).
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
        accessibilityIdentifier: String = "DesignPreview-RangeSlider",
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
        // Leading-origin lit fill, right cap centred under the knob — same seam
        // trick the zoom slider and CenterSlider use.
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
            // One step = 1% of the range, matching the zoom slider's feel.
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

/// Leading-origin detented slider over a `Double` range with a fixed `step`.
/// Shares `GlassSliderRail` and the same knob travel geometry as `RangeSlider` /
/// `CenterSlider` (`travel = trackWidth - knobSize`), draws one dot per detent,
/// and live-snaps the knob onto notches while dragging.
public struct DetentedRangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var accessibilityLabel: String = "Range slider"
    var accessibilityValue: String = ""
    var accessibilityIdentifier: String = "DesignPreview-DetentedRangeSlider"
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
        accessibilityIdentifier: String = "DesignPreview-DetentedRangeSlider",
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
        .modifier(DetentedSliderTickSensoryModifier(
            value: snappedValue,
            lowerBound: range.lowerBound,
            upperBound: range.upperBound
        ))
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

/// visionOS detent ticks for glass sliders: end stops play selection min/max,
/// mid notches play increase/decrease. Press and release stay on the host slider.
private struct DetentedSliderTickSensoryModifier<Value: Comparable & Equatable>: ViewModifier {
    let value: Value
    let lowerBound: Value
    let upperBound: Value

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content.sensoryFeedback(trigger: value) { old, new in
            if new == old { return nil }
            if new == lowerBound { return .selection(.minimum) }
            if new == upperBound { return .selection(.maximum) }
            return new > old ? .increase : .decrease
        }
        #else
        content
        #endif
    }
}
