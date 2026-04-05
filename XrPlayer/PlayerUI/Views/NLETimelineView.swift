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
struct NLETimelineView: View {

    @Binding var isExpanded: Bool

    /// Current playback position in seconds (drives ruler + playhead).
    let currentTime: Double
    /// Total media duration in seconds.
    let duration: Double

    /// Called with target time when user drags on the thumb strip.
    var onSeek: ((Double) -> Void)?
    /// Called when user taps frame-step-forward button.
    var onFrameStepForward: (() -> Void)?
    /// Called when user taps frame-step-backward button.
    var onFrameStepBackward: (() -> Void)?

    // MARK: - State

    @State private var zoomLevel: Double?

    // MARK: - Layout constants

    private let expandedHeight: CGFloat = 160
    private let panelWidth: CGFloat = 680

    /// Resolved zoom: explicit state or duration-based default.
    private var resolvedZoom: Double {
        zoomLevel ?? TimelineRulerView.defaultZoom(for: duration)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                timelineContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: panelWidth)
        .frame(height: isExpanded ? expandedHeight : 0, alignment: .top)
        .clipped()
        .enchronGlassPanel()
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.Radius.card,
                style: .continuous
            )
        )
        .animation(.spring(), value: isExpanded)
        .gesture(zoomGesture)
    }

    // MARK: - Timeline Content

    @ViewBuilder
    private var timelineContent: some View {
        VStack(spacing: 8) {
            TimelineRulerView(
                duration: duration,
                currentTime: currentTime,
                isSeeking: false,
                zoomLevel: resolvedZoom
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
            .frame(minWidth: 60, minHeight: 36)
            .contentShape(.rect)

            Spacer()

            Button {
                onFrameStepForward?()
            } label: {
                Label("Next Frame", systemImage: "forward.frame")
                    .font(.caption)
                    .foregroundStyle(Color.enchronOnSurface.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 60, minHeight: 36)
            .contentShape(.rect)
        }
    }

    // MARK: - Zoom Gesture

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let baseZoom = zoomLevel ?? TimelineRulerView.defaultZoom(for: duration)
                let newZoom = baseZoom * value.magnification
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
                .frame(minWidth: 60, minHeight: 60)
                .contentShape(.rect)
        }
        .buttonStyle(.automatic)
        .help(isExpanded ? "Collapse Timeline" : "Expand Timeline")
        .accessibilityLabel(isExpanded ? "Collapse timeline" : "Expand timeline")
        .accessibilityAddTraits(.isToggle)
    }
}

#Preview("Expanded") {
    VStack(spacing: 12) {
        NLETimelineToggleButton(isExpanded: .constant(true))
        NLETimelineView(
            isExpanded: .constant(true),
            currentTime: 125.5,
            duration: 3600
        )
    }
    .padding()
}

#Preview("Collapsed") {
    VStack(spacing: 12) {
        NLETimelineToggleButton(isExpanded: .constant(false))
        NLETimelineView(
            isExpanded: .constant(false),
            currentTime: 0,
            duration: 3600
        )
    }
    .padding()
}
