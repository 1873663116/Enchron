import SwiftUI

/// Expandable NLE (non-linear editing) timeline panel that slides below the
/// player control bar.  Hosts the time ruler (Unit 15), thumb strip (Unit 16),
/// frame step buttons, and zoom gesture.
///
/// Toggle behaviour:
///   - Collapsed: panel is hidden via `clipped()` + zero height.
///   - Expanded: panel slides open with `.spring` animation.
///
/// Glass material: `.enchronGlassPanel()` (regularMaterial).
///
/// Note: `currentTime` and `duration` are read from the `WindowVideoViewModel`
/// environment directly so that the 200ms polling loop invalidates only this
/// view — not the parent `PlayerControlsView` body.
struct NLETimelineView: View {

    @Binding var isExpanded: Bool

    // Read playbackPosition here so the 200ms update cycle only re-evaluates
    // NLETimelineView, not the entire PlayerControlsView body.
    @Environment(WindowVideoViewModel.self) private var videoViewModel

    /// Called with target time when user drags on the thumb strip.
    var onSeek: ((Double) -> Void)?
    /// Called when user taps frame-step-forward button.
    var onFrameStepForward: (() -> Void)?
    /// Called when user taps frame-step-backward button.
    var onFrameStepBackward: (() -> Void)?

    private var currentTime: Double { videoViewModel.playbackPosition.seconds }
    private var duration: Double { videoViewModel.playbackPosition.duration }

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoomLevel: Double?
    @GestureState private var gestureStartZoom: Double?

    // MARK: - Layout constants

    private let expandedHeight: CGFloat = 180
    private let panelWidth: CGFloat = DesignTokens.Layout.playerControlsWidth

    /// Resolved zoom: explicit state or duration-based default.
    private var resolvedZoom: Double {
        zoomLevel ?? TimelineRulerView.defaultZoom(for: duration)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                timelineContent
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(width: panelWidth)
        .frame(height: isExpanded ? expandedHeight : 0, alignment: .top)
        .clipped()
        .glassBackgroundEffect(
            in: RoundedRectangle(
                cornerRadius: DesignTokens.Radius.card,
                style: .continuous
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 0.5)
        }
        .animation(reduceMotion ? .easeInOut : .spring(), value: isExpanded)
        .gesture(zoomGesture)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline")
        .accessibilityAction(named: "Seek Forward") {
            let target = min(duration, currentTime + 10)
            onSeek?(target)
        }
        .accessibilityAction(named: "Seek Backward") {
            let target = max(0, currentTime - 10)
            onSeek?(target)
        }
        .accessibilityAction(named: "Next Frame") {
            onFrameStepForward?()
        }
        .accessibilityAction(named: "Previous Frame") {
            onFrameStepBackward?()
        }
    }

    // MARK: - Timeline Content

    @ViewBuilder
    private var timelineContent: some View {
        VStack(spacing: 8) {
            TimelineRulerView(
                duration: duration,
                currentTime: currentTime,
                isSeeking: false,
                zoomLevel: resolvedZoom,
                onSeek: onSeek
            )

            ThumbStripView(
                duration: duration,
                currentTime: currentTime,
                zoomLevel: resolvedZoom,
                onSeek: onSeek
            )

            frameStepRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .hoverEffect(.highlight)
    }

    // MARK: - Frame Step Buttons

    private var frameStepRow: some View {
        HStack {
            Button {
                onFrameStepBackward?()
            } label: {
                Label("Previous Frame", systemImage: "backward.frame")
                    .font(.caption)
                    .foregroundStyle(Color.enchronOnSurface.opacity(0.7))
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .frame(minWidth: 44, minHeight: 36)
            .contentShape(.rect)
            .accessibilityLabel("Previous Frame")
            .accessibilityHint("Steps backward one frame")

            Spacer()

            Button {
                onFrameStepForward?()
            } label: {
                Label("Next Frame", systemImage: "forward.frame")
                    .font(.caption)
                    .foregroundStyle(Color.enchronOnSurface.opacity(0.7))
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .frame(minWidth: 44, minHeight: 36)
            .contentShape(.rect)
            .accessibilityLabel("Next Frame")
            .accessibilityHint("Steps forward one frame")
        }
    }

    // MARK: - Zoom Gesture

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureStartZoom) { _, state, _ in
                if state == nil {
                    state = zoomLevel ?? TimelineRulerView.defaultZoom(for: duration)
                }
            }
            .onChanged { value in
                let base = gestureStartZoom ?? zoomLevel ?? TimelineRulerView.defaultZoom(for: duration)
                let newZoom = base * value.magnification
                zoomLevel = max(0, min(1, newZoom))
            }
    }
}

// MARK: - Toggle Button

/// A small button used in the control bar to expand/collapse the NLE timeline.
struct NLETimelineToggleButton: View {

    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: isExpanded ? "timeline.selection" : "timeline.selection")
                .font(.title3)
                .foregroundStyle(isExpanded ? Color.enchronTertiary : .primary)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .help(isExpanded ? "Collapse Timeline" : "Expand Timeline")
        .accessibilityLabel(isExpanded ? "Collapse timeline" : "Expand timeline")
        .accessibilityAddTraits(.isToggle)
    }
}

#Preview("Expanded") {
    let vm = WindowVideoViewModel(player: MPVPlayerAdapter())
    VStack(spacing: 12) {
        NLETimelineToggleButton(isExpanded: .constant(true))
        NLETimelineView(isExpanded: .constant(true))
    }
    .environment(vm)
    .padding()
}

#Preview("Collapsed") {
    let vm = WindowVideoViewModel(player: MPVPlayerAdapter())
    VStack(spacing: 12) {
        NLETimelineToggleButton(isExpanded: .constant(false))
        NLETimelineView(isExpanded: .constant(false))
    }
    .environment(vm)
    .padding()
}
