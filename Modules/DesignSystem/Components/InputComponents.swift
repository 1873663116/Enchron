import SwiftUI

struct GlassToggle: View {
    @State var isOn: Bool

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
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

struct BoundGlassToggle: View {
    @Binding var isOn: Bool
    var isEnabled = true

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
        .glassBackgroundEffect(in: Capsule())
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
struct GlassSliderRail: View {
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

    var body: some View {
        Capsule()
            .fill(DesignTokens.Surface.elevated)
            .frame(width: trackWidth, height: trackHeight)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: max(litWidth, 0), height: trackHeight)
                    .glassBackgroundEffect(in: Capsule())
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
            .glassBackgroundEffect(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.highlight)
    }
}

/// `CenterSlider` is the macro component; a `CenterDetentSlider` specialization
/// can be split out later if a non-detented (continuous) variant is needed.
struct CenterSlider: View {
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

    var body: some View {
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
struct RangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: String = "Range slider"
    var accessibilityValue: String = ""
    var accessibilityIdentifier: String = "DesignPreview-RangeSlider"
    var trackWidth: CGFloat = 450
    /// 拖动状态上抛给宿主行(见 CenterSlider.onDraggingChanged)。
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

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

    var body: some View {
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
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
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
