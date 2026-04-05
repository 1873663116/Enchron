import SwiftUI

/// Expandable NLE (non-linear editing) timeline panel that slides below the
/// player control bar.  Currently hosts placeholder content for the ruler
/// (Unit 15) and thumb strip (Unit 16) — those will replace the placeholders.
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

    // MARK: - Layout constants

    private let expandedHeight: CGFloat = 120
    private let panelWidth: CGFloat = 680

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
    }

    // MARK: - Timeline Content

    @ViewBuilder
    private var timelineContent: some View {
        VStack(spacing: 8) {
            TimelineRulerView(
                duration: duration,
                currentTime: currentTime,
                isSeeking: false
            )

            // Thumb strip placeholder — will be replaced by ThumbStripView (Unit 16)
            thumbStripPlaceholder
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var thumbStripPlaceholder: some View {
        Rectangle()
            .fill(Color.enchronSurfaceContainerLow.opacity(0.3))
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                Text("Timeline")
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(Color.enchronOnSurface.opacity(0.35))
                    .textCase(.uppercase)
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
