import SwiftUI

public enum EnchronPressSensoryFeedback {
    case button
    case iconOnly
    /// visionOS slider thumb touch-down (`press(.slider)`).
    case slider
    /// visionOS slider thumb touch-up (`release(.slider)`).
    case sliderRelease
    /// Discrete step upward (`increase`); plays on visionOS.
    case increase
    /// Discrete step downward (`decrease`); plays on visionOS.
    case decrease
    case selectionMinimum
    case selectionMaximum
    case selectionOn
}

/// Seek scrub sensory: press, release, and end stops only. Mid-track dragging
/// intentionally stays silent — continuous ticks are not part of this family.
public enum EnchronScrubBoundary: Equatable, Sendable {
    case none
    case minimum
    case maximum

    public static func from(normalized: Double) -> EnchronScrubBoundary {
        if normalized <= 0 { return .minimum }
        if normalized >= 1 { return .maximum }
        return .none
    }
}

public extension View {
    @ViewBuilder
    func enchronPressSensoryFeedback<T: Equatable>(
        _ feedback: EnchronPressSensoryFeedback,
        trigger: T
    ) -> some View {
        #if os(visionOS)
        switch feedback {
        case .button:
            sensoryFeedback(.press(.button), trigger: trigger)
        case .iconOnly:
            sensoryFeedback(.press(.buttonIconOnly), trigger: trigger)
        case .slider:
            sensoryFeedback(.press(.slider), trigger: trigger)
        case .sliderRelease:
            sensoryFeedback(.release(.slider), trigger: trigger)
        case .increase:
            sensoryFeedback(.increase, trigger: trigger)
        case .decrease:
            sensoryFeedback(.decrease, trigger: trigger)
        case .selectionMinimum:
            sensoryFeedback(.selection(.minimum), trigger: trigger)
        case .selectionMaximum:
            sensoryFeedback(.selection(.maximum), trigger: trigger)
        case .selectionOn:
            sensoryFeedback(.selection(.on), trigger: trigger)
        }
        #else
        self
        #endif
    }

    /// Press / release for a scrubbing control, plus selection min/max when the
    /// value lands on an end stop. Mid-range scrubbing does not play ticks.
    ///
    /// Hosts should keep `boundary` mirrored while idle so the first drag frame
    /// does not jump from a stale value and fire a false end cue. Pass
    /// `boundariesEnabled` only while the gesture is actively scrubbing.
    func enchronScrubSensoryFeedback(
        pressTrigger: Int,
        releaseTrigger: Int,
        boundary: EnchronScrubBoundary,
        boundariesEnabled: Bool
    ) -> some View {
        modifier(
            EnchronScrubSensoryModifier(
                pressTrigger: pressTrigger,
                releaseTrigger: releaseTrigger,
                boundary: boundary,
                boundariesEnabled: boundariesEnabled
            )
        )
    }
}

private struct EnchronScrubSensoryModifier: ViewModifier {
    let pressTrigger: Int
    let releaseTrigger: Int
    let boundary: EnchronScrubBoundary
    let boundariesEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        content
            .enchronPressSensoryFeedback(.slider, trigger: pressTrigger)
            .enchronPressSensoryFeedback(.sliderRelease, trigger: releaseTrigger)
            .sensoryFeedback(trigger: boundary) { old, new in
                guard boundariesEnabled, new != old else { return nil }
                switch new {
                case .minimum: return .selection(.minimum)
                case .maximum: return .selection(.maximum)
                case .none: return nil
                }
            }
        #else
        content
        #endif
    }
}

public enum EnchronPressFeedbackStyle {
    case card
    case row
    case control
    case icon

    var spec: DesignTokens.PressFeedbackSpec {
        switch self {
        case .card:
            DesignTokens.PressFeedback.card
        case .row:
            DesignTokens.PressFeedback.row
        case .control:
            DesignTokens.PressFeedback.control
        case .icon:
            DesignTokens.PressFeedback.icon
        }
    }

    var sensoryFeedback: EnchronPressSensoryFeedback {
        switch self {
        case .icon:
            .iconOnly
        case .card, .row, .control:
            .button
        }
    }
}

public struct EnchronPressFeedbackButtonStyle: ButtonStyle {
    let style: EnchronPressFeedbackStyle
    let playsSensoryFeedback: Bool

    public init(
        _ style: EnchronPressFeedbackStyle,
        playsSensoryFeedback: Bool = false
    ) {
        self.style = style
        self.playsSensoryFeedback = playsSensoryFeedback
    }

    /// Icon chrome for system `Menu` labels: same press scale as
    /// `GlassCircleIconButton`, plus explicit icon-only sensory feedback.
    public static func menuIcon() -> EnchronPressFeedbackButtonStyle {
        EnchronPressFeedbackButtonStyle(.icon, playsSensoryFeedback: true)
    }

    public func makeBody(configuration: Configuration) -> some View {
        EnchronPressFeedbackButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            style: style,
            playsSensoryFeedback: playsSensoryFeedback
        )
    }
}

private struct EnchronPressFeedbackButtonStyleBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let style: EnchronPressFeedbackStyle
    let playsSensoryFeedback: Bool

    @State private var measuredSize: CGSize = .zero
    @State private var isVisuallyPressed = false
    @State private var pressStartedAt: ContinuousClock.Instant?
    @State private var transitionGeneration = 0
    @State private var sensoryTrigger = 0

    var body: some View {
        let spec = style.spec

        label
            .scaleEffect(isVisuallyPressed ? spec.effectivePressedScale(for: measuredSize) : 1.0)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            measuredSize = newSize
                        }
                }
            }
            .onChange(of: isPressed, initial: true) { _, newValue in
                transitionGeneration += 1
                let generation = transitionGeneration
                let clock = ContinuousClock()

                if newValue {
                    if playsSensoryFeedback {
                        sensoryTrigger += 1
                    }
                    pressStartedAt = clock.now
                    withAnimation(spec.pressAnimation) {
                        isVisuallyPressed = true
                    }
                } else if isVisuallyPressed {
                    let elapsed = pressStartedAt?.duration(to: clock.now) ?? spec.holdDuration
                    let remaining = elapsed < spec.holdDuration
                        ? spec.holdDuration - elapsed
                        : .zero
                    pressStartedAt = nil

                    Task { @MainActor in
                        if remaining > .zero {
                            try? await Task.sleep(for: remaining)
                        }
                        guard generation == transitionGeneration else { return }

                        withAnimation(spec.releaseAnimation) {
                            isVisuallyPressed = false
                        }
                    }
                }
            }
            .modifier(
                EnchronOptionalPressSensoryModifier(
                    feedback: style.sensoryFeedback,
                    trigger: sensoryTrigger,
                    isEnabled: playsSensoryFeedback
                )
            )
    }
}

private struct EnchronOptionalPressSensoryModifier<T: Equatable>: ViewModifier {
    let feedback: EnchronPressSensoryFeedback
    let trigger: T
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.enchronPressSensoryFeedback(feedback, trigger: trigger)
        } else {
            content
        }
    }
}
