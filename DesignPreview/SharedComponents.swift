import SwiftUI

// MARK: - Shared components used by the Design System review pages

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
        let press = DesignTokens.PressFeedback.icon

        ZStack {
            HStack(spacing: 0) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(iconColor)
                    .scaleEffect(pressedSide == .back ? press.pressedScale : 1.0)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                Image(systemName: "chevron.right")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(iconColor.opacity(trailingOpacity))
                    .scaleEffect(pressedSide == .forward ? press.pressedScale : 1.0)
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
                withAnimation(press.pressAnimation) { pressedSide = tapped }
                Task {
                    try? await Task.sleep(for: press.holdDuration)
                    withAnimation(press.releaseAnimation) { pressedSide = nil }
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
        let press = DesignTokens.PressFeedback.icon

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
                withAnimation(press.pressAnimation) { pressedIndex = tapped }
                Task {
                    try? await Task.sleep(for: press.holdDuration)
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
        let press = DesignTokens.PressFeedback.icon

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
                .scaleEffect(isPressed ? press.pressedScale : 1.0)
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
        .enchronPressFeedback(.card)
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
        .enchronPressFeedback(.card)
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
        .enchronPressFeedback(.card)
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
        .enchronPressFeedback(.row)
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
        .enchronPressFeedback(.row)
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
        .enchronPressFeedback(.row)
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
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

struct MockBreadcrumb: View {
    let path: [String]
    let onSelectLevel: (Int) -> Void

    init(
        path: [String] = ["Local Storage", "Movies"],
        onSelectLevel: @escaping (Int) -> Void = { _ in }
    ) {
        self.path = path
        self.onSelectLevel = onSelectLevel
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(Array(path.enumerated()), id: \.offset) { index, node in
                Button(node) {
                    onSelectLevel(index)
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.lift)
                .contentShape(Capsule())

                if index < path.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
        }
    }
}

struct PlayerProgressBar: View {
    private enum InteractionState {
        case normal
        case hover
        case active
    }

    @State private var progress: CGFloat = 0.45
    @State private var isStripHovered = false
    @State private var isThumbHovered = false
    @State private var isDragging = false

    private var interactionState: InteractionState {
        if isDragging { return .active }
        if isStripHovered || isThumbHovered { return .hover }
        return .normal
    }

    private var isRevealed: Bool {
        interactionState != .normal
    }

    private var trackHeight: CGFloat {
        interactionState == .active
            ? DesignTokens.ProgressBar.trackHeight
            : DesignTokens.ProgressBar.inactiveTrackHeight
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - DesignTokens.ProgressBar.thumbDiameter, 0)
            let clampedProgress = min(max(progress, 0), 1)
            let thumbX = DesignTokens.ProgressBar.thumbDiameter / 2 + clampedProgress * width
            let overlayWidth = width + DesignTokens.ProgressBar.thumbDiameter

            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
                    .accessibilityHidden(true)

                progressHub(
                    width: width,
                    progress: clampedProgress,
                    overlayWidth: overlayWidth,
                    playedColor: isRevealed
                        ? DesignTokens.ProgressBar.playedHoverColor
                        : DesignTokens.ProgressBar.playedColor,
                    unplayedColor: isRevealed
                        ? DesignTokens.ProgressBar.unplayedHoverColor
                        : DesignTokens.ProgressBar.unplayedColor,
                    height: trackHeight
                )

                timeBubble
                    .position(
                        x: thumbX,
                        y: DesignTokens.ProgressBar.hitHeight / 2 - DesignTokens.ProgressBar.timeBubbleOffset
                    )
                    .opacity(isRevealed ? 1.0 : 0.0)
                    .animation(DesignTokens.AnimationToken.selection, value: isRevealed)
                    .allowsHitTesting(false)

                scrubberControl(width: width)
                    .position(
                        x: thumbX,
                        y: DesignTokens.ProgressBar.hitHeight / 2
                    )
                    .opacity(isRevealed ? 1.0 : 0.0)
                    .animation(DesignTokens.AnimationToken.selection, value: isRevealed)
            }
            .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(.interaction, Capsule())
            .onHover { isHovering in
                setStripHovered(isHovering)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    setStripHovered(true)
                case .ended:
                    setStripHovered(false)
                }
            }
            .gesture(dragGesture(width: width))
        }
        .frame(height: DesignTokens.ProgressBar.hitHeight)
        .accessibilityIdentifier("DesignPreview-PlayerProgressBar")
        .accessibilityLabel("Playback progress")
    }

    private func progressHub(
        width: CGFloat,
        progress: CGFloat,
        overlayWidth: CGFloat,
        playedColor: Color,
        unplayedColor: Color,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            progressTrack(
                width: width,
                progress: progress,
                playedColor: playedColor,
                unplayedColor: unplayedColor,
                height: height
            )
            .padding(.leading, DesignTokens.ProgressBar.thumbDiameter / 2)
        }
            .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
    }

    private func progressTrack(
        width: CGFloat,
        progress: CGFloat,
        playedColor: Color,
        unplayedColor: Color,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(unplayedColor)
            Capsule()
                .fill(playedColor)
                .frame(width: width * progress)
        }
        .frame(width: width, height: height)
        .animation(DesignTokens.AnimationToken.selection, value: height)
        .animation(DesignTokens.AnimationToken.selection, value: playedColor)
        .animation(DesignTokens.AnimationToken.selection, value: unplayedColor)
    }

    private var timeBubble: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text("6:21")
                .foregroundStyle(.primary)
            Text("-7:54")
                .foregroundStyle(.secondary)
        }
        .font(DesignTokens.Typography.monospacedDetail)
        .monospacedDigit()
        .padding(.horizontal, DesignTokens.ProgressBar.timeBubblePaddingH)
        .padding(.vertical, DesignTokens.ProgressBar.timeBubblePaddingV)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.ProgressBar.timeBubbleRadius, style: .continuous)
                .fill(DesignTokens.ProgressBar.timeBubbleFill)
        )
    }

    private func scrubberThumbVisual() -> some View {
        Circle()
            .fill(.white)
            .overlay {
                Circle()
                    .strokeBorder(
                        DesignTokens.ProgressBar.thumbStroke,
                        lineWidth: DesignTokens.ProgressBar.thumbStrokeWidth
                    )
            }
            .frame(width: DesignTokens.ProgressBar.thumbDiameter,
                   height: DesignTokens.ProgressBar.thumbDiameter)
    }

    private func scrubberThumb() -> some View {
        scrubberThumbVisual()
            .accessibilityIdentifier("DesignPreview-PlayerProgressBar-thumb")
            .accessibilityLabel("Playback position thumb")
    }

    private func scrubberControl(width: CGFloat) -> some View {
        scrubberThumb()
            .contentShape(.hoverEffect, Circle())
            .hoverEffect()
            .onHover { isHovering in
                isThumbHovered = isHovering
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isThumbHovered = true
                case .ended:
                    isThumbHovered = false
                }
            }
            .frame(width: DesignTokens.ProgressBar.hitHeight,
                   height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(Circle())
            .allowsHitTesting(isRevealed || isDragging)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    beginScrubbing()
                }
                isDragging = true
                progress = progress(forLocation: value.location.x, width: width)
            }
            .onEnded { _ in
                endScrubbing()
            }
    }

    private func beginScrubbing() {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isDragging = true
        }
    }

    private func endScrubbing() {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isDragging = false
        }
    }

    private func setStripHovered(_ isHovered: Bool) {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isStripHovered = isHovered
            if !isHovered {
                isThumbHovered = false
            }
        }
    }

    private func progress(forLocation locationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return progress }
        let trackStartX = DesignTokens.ProgressBar.thumbDiameter / 2
        return min(max((locationX - trackStartX) / width, 0), 1)
    }
}

struct PlayerProgressStrip: View {
    var body: some View {
        PlayerProgressBar()
        .frame(width: DesignTokens.ProgressBar.previewWidth)
        .accessibilityIdentifier("DesignPreview-PlayerProgressStrip")
        .accessibilityLabel("Playback progress")
    }
}

struct PlayerControlBar: View {
    var body: some View {
        HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
            controlButton("line.3.horizontal", label: "Playlist")
            controlButton("gobackward.10", label: "Rewind 10 seconds")
            primaryPlayButton
            controlButton("goforward.10", label: "Forward 10 seconds")
            controlButton("slider.horizontal.3", label: "Playback settings")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.ControlBar.paddingH)
        .padding(.vertical, DesignTokens.ControlBar.paddingV)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: .capsule)
        .contentShape(Capsule())
    }

    private var primaryPlayButton: some View {
        Button {} label: {
            Image(systemName: "play.fill")
                .font(DesignTokens.SymbolSize.action)
                .foregroundStyle(DesignTokens.ControlBar.primarySymbol)
                .frame(width: DesignTokens.Interactive.xl,
                       height: DesignTokens.Interactive.xl)
                .background(DesignTokens.ControlBar.primaryFill, in: Circle())
        }
        .buttonStyle(.plain)
        .enchronPressFeedback(.icon)
        .clipShape(Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PlayerControlBar-button-play")
        .accessibilityLabel("Play")
    }

    private func controlButton(_ systemName: String, label: String) -> some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(DesignTokens.SymbolSize.control)
                .frame(width: DesignTokens.Interactive.large,
                       height: DesignTokens.Interactive.large)
        }
        .buttonStyle(.plain)
        .enchronPressFeedback(.icon)
        .clipShape(Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PlayerControlBar-button-\(label)")
        .accessibilityLabel(label)
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

    var body: some View {
        let lineWidth = size * 0.06
        let inset = size * 0.16

        ZStack {
            // Glow layer — theme-colored, screen blend, follows arc
            SpinnerArc(start: arcStart, end: arcEnd)
                .stroke(
                    DesignTokens.Theme.accent.opacity(0.15),
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
                    .strokeBorder(DesignTokens.Theme.accent.opacity(0.3), lineWidth: 1)
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
                withAnimation(DesignTokens.LoadingSpinner.headAnimation) {
                    arcEnd = 0.85
                }
                try? await Task.sleep(for: DesignTokens.LoadingSpinner.headDuration)

                // Tail catches up to head
                withAnimation(DesignTokens.LoadingSpinner.tailAnimation) {
                    arcStart = 0.85
                }
                try? await Task.sleep(for: DesignTokens.LoadingSpinner.tailDuration)

                // Instant reset to start position
                arcStart = 0
                arcEnd = 0
            }
        }
    }
}
