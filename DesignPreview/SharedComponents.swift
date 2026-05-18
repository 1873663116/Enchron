import SwiftUI

// MARK: - Shared components used across multiple mockup pages
// These are NOT private — they're referenced by BrowseMockup, PlayerMockup, and ComponentLibrary.

// MARK: - Reusable controls

struct NavBackForwardCapsuleControl: View {
    var iconColor: Color = .white
    var trailingOpacity: Double = 0.65
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var accessibilityIdentifier: String = "DesignPreview-control-navBackForward"
    var accessibilityLabel: String = "Back and Forward"

    @State private var pressedSide: NavSide? = nil

    private enum NavSide { case back, forward }

    var body: some View {
        let capsuleWidth = DesignTokens.Interactive.regular * 2

        ZStack {
            HStack(spacing: 0) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(iconColor)
                    .scaleEffect(pressedSide == .back ? 0.95 : 1.0)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                Image(systemName: "chevron.right")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(iconColor.opacity(trailingOpacity))
                    .scaleEffect(pressedSide == .forward ? 0.95 : 1.0)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
            }
            .frame(width: capsuleWidth, height: DesignTokens.Interactive.regular)
            .enchronGlassControl()
        }
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                let tapped: NavSide = value.location.x < capsuleWidth / 2 ? .back : .forward
                withAnimation(.easeOut(duration: 0.08)) { pressedSide = tapped }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressedSide = nil }
                }
                if tapped == .back { onBack() } else { onForward() }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap left half for back, right half for forward")
    }
}

struct ViewModeCapsuleControl: View {
    @Binding var selection: Int
    var iconColor: Color = .white
    var unselectedOpacity: Double = 0.45
    var accessibilityIdentifier: String = "DesignPreview-control-viewMode"
    var accessibilityLabel: String = "View Mode"

    @Namespace private var indicatorNamespace
    @State private var pressedIndex: Int? = nil

    var body: some View {
        let capsuleWidth = DesignTokens.Interactive.regular * 2

        ZStack {
            HStack(spacing: 0) {
                viewModeIcon("square.grid.2x2", isSelected: selection == 0, isPressed: pressedIndex == 0)
                viewModeIcon("list.bullet", isSelected: selection == 1, isPressed: pressedIndex == 1)
            }
            .frame(width: capsuleWidth, height: DesignTokens.Interactive.regular)
            .enchronGlassControl()
        }
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                let tapped = value.location.x < capsuleWidth / 2 ? 0 : 1
                withAnimation(.easeOut(duration: 0.08)) { pressedIndex = tapped }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(DesignTokens.AnimationToken.selection) {
                        selection = tapped
                        pressedIndex = nil
                    }
                }
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap left half for grid, right half for list")
    }

    @ViewBuilder
    private func viewModeIcon(_ icon: String, isSelected: Bool, isPressed: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(DesignTokens.Surface.selected)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                    .matchedGeometryEffect(id: "viewModeIndicator", in: indicatorNamespace)
            }

            Image(systemName: icon)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(isSelected ? iconColor : iconColor.opacity(unselectedOpacity))
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
    }
}

// MARK: - Cards

struct VideoCardLarge: View {
    let title: String
    let fileSize: String
    let duration: String
    var badges: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail + badges
            ZStack(alignment: .topTrailing) {
                // Thumbnail placeholder — in real app this is the video frame
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Surface.elevated)
                    .frame(height: 140)

                // Badges (HDR, DV, etc.) — Capsule, top-right
                if !badges.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(DesignTokens.Typography.badge)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, DesignTokens.Spacing.xs)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .enchronGlassBadge()
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                }
            }

            // Info: title, then fileSize left + duration right
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title).font(DesignTokens.Typography.headline)
                HStack {
                    Text(fileSize)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(duration)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, DesignTokens.Card.paddingH)
            .padding(.vertical, DesignTokens.Card.paddingV)
        }
        .frame(width: DesignTokens.Card.gridMin)
        .enchronGlassCard()
    }
}

struct FolderCard: View {
    let title: String
    let count: Int

    var body: some View {
        let shape = DesignTokens.ShapeToken.card
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Surface.elevated)
                .frame(height: 140)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.tertiary)
                        .hoverEffect { effect, isActive, _ in
                            effect.animation(.default.delay(isActive ? 0.15 : 0.05)) {
                                $0.scaleEffect(isActive ? 1.1 : 1.0)
                            }
                        }
                }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title).font(DesignTokens.Typography.headline)
                Text("\(count) items")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.Card.paddingH)
            .padding(.vertical, DesignTokens.Card.paddingV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: DesignTokens.Card.gridMin)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .contentShape(shape)
        .hoverEffectGroup()
    }
}

struct SceneCardMedium: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(DesignTokens.SymbolSize.feature)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 100, height: 80)
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(DesignTokens.Spacing.sm)
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: DesignTokens.Stroke.bold)
                : nil
        )
        .enchronGlassCard()
    }
}

// MARK: - Row items

struct FileListRow: View {
    let icon: String
    let title: String
    let metadata: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title).font(.body)
            Spacer()
            Text(metadata)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
    }
}

struct MenuItemRow: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(isExpanded ? .degrees(90) : .zero)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
    }
}

struct SubMenuItemRow: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
    }
}

// MARK: - Small elements

struct MockToggle: View {
    @State var isOn: Bool

    var body: some View {
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? Color(red: 0.224, green: 0.773, blue: 0.733) : DesignTokens.Surface.elevated)
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
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

// MARK: - Loading spinner

/// Arc shape with independently animatable start/end values.
private struct SpinnerArc: Shape {
    var start: CGFloat
    var end: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) * 0.38,
            startAngle: .degrees(start * 360 - 120),
            endAngle: .degrees(end * 360 - 120),
            clockwise: false
        )
        return path
    }
}

struct LoadingSpinner: View {
    var size: CGFloat = 56
    var showBorder: Bool = true

    @State private var arcStart: CGFloat = 0
    @State private var arcEnd: CGFloat = 0

    private static let themeColor = Color(red: 0.224, green: 0.773, blue: 0.733)

    var body: some View {
        let lineWidth = size * 0.06
        let inset = size * 0.16

        ZStack {
            // Glow layer — theme-colored, screen blend, follows arc
            SpinnerArc(start: arcStart, end: arcEnd)
                .stroke(
                    Self.themeColor.opacity(0.15),
                    style: StrokeStyle(lineWidth: lineWidth * 4, lineCap: .round)
                )
                .blur(radius: lineWidth * 2)
                .blendMode(.screen)
                .padding(inset)

            // White arc
            SpinnerArc(start: arcStart, end: arcEnd)
                .stroke(
                    .white.opacity(0.9),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .padding(inset)
        }
        .frame(width: size, height: size)
        .overlay {
            if showBorder {
                Circle()
                    .strokeBorder(Self.themeColor.opacity(0.3), lineWidth: 1)
            }
        }
        .clipShape(Circle())
        .glassBackgroundEffect(in: Circle())
        .onAppear { runLoop() }
    }

    private func runLoop() {
        Task {
            while !Task.isCancelled {
                // Head extends forward from gap
                withAnimation(.easeOut(duration: 0.7)) {
                    arcEnd = 0.85
                }
                try? await Task.sleep(for: .milliseconds(700))

                // Tail catches up to head
                withAnimation(.easeOut(duration: 0.55)) {
                    arcStart = 0.85
                }
                try? await Task.sleep(for: .milliseconds(550))

                // Instant reset to start position
                arcStart = 0
                arcEnd = 0
            }
        }
    }
}
