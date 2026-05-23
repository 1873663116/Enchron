import SwiftUI

// MARK: - Shared components used by the Design System review pages

// MARK: - Reusable controls

struct GlassCircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var action: () -> Void = {}
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(iconColor)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Circle())
        .glassBackgroundEffect(in: Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.automatic)
        .padding((DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Circle())
        .enchronPressFeedback(.icon)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-button-\(systemName)")
    }
}

struct GlassCapsuleIconLabelButton: View {
    let title: String
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var minWidth: CGFloat = DesignTokens.Interactive.regular * 2
    var action: () -> Void = {}
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(iconColor)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minWidth: minWidth, minHeight: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Capsule())
        .enchronPressFeedback(.control)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-button-\(title)")
    }
}

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
    var width: CGFloat = DesignTokens.Card.gridMin

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail + badges
            ZStack(alignment: .topTrailing) {
                // Thumbnail placeholder — in real app this is the video frame
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Surface.elevated)
                    .frame(height: DesignTokens.Card.thumbnailHeight)

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
        .frame(width: width)
        .enchronGlassCard()
        .enchronPressFeedback(.card)
    }
}

struct FolderCard: View {
    let title: String
    let count: Int
    var width: CGFloat = DesignTokens.Card.gridMin

    var body: some View {
        let shape = DesignTokens.ShapeToken.card
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Surface.elevated)
                .frame(height: DesignTokens.Card.thumbnailHeight)
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
        .frame(width: width)
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

struct FeaturedScene: Identifiable {
    let id: String
    let imageName: String
    let title: String
    let sceneNumber: String
    let quote: String
    let mode: String
    let atmosphere: String

    static let fixtures: [FeaturedScene] = [
        .init(
            id: "snow-village",
            imageName: "SceneFeatureCard",
            title: "Snow Village",
            sceneNumber: "Scene 01",
            quote: "\"A bright winter morning opens into a quiet alpine town.\"",
            mode: "Spatial cinema",
            atmosphere: "Snowfield / clear daylight"
        ),
        .init(
            id: "dune-observatory",
            imageName: "SceneFeatureDesert",
            title: "Dune Observatory",
            sceneNumber: "Scene 02",
            quote: "\"A gold horizon turns the theatre into a quiet instrument.\"",
            mode: "Observatory cinema",
            atmosphere: "Desert / amber dusk"
        ),
        .init(
            id: "neon-canopy",
            imageName: "SceneFeatureNeonCity",
            title: "Neon Canopy",
            sceneNumber: "Scene 03",
            quote: "\"Rain and city light fold into a private rooftop screen.\"",
            mode: "Night lounge",
            atmosphere: "Neon / reflective rain"
        ),
        .init(
            id: "forest-shrine",
            imageName: "SceneFeatureForestShrine",
            title: "Forest Shrine",
            sceneNumber: "Scene 04",
            quote: "\"The woods dim the world without closing it in.\"",
            mode: "Ambient cinema",
            atmosphere: "Moss / morning mist"
        ),
        .init(
            id: "ocean-temple",
            imageName: "SceneFeatureOceanTemple",
            title: "Ocean Temple",
            sceneNumber: "Scene 05",
            quote: "\"Light falls through water and softens every edge.\"",
            mode: "Deep cinema",
            atmosphere: "Coral / turquoise depth"
        ),
        .init(
            id: "orbital-garden",
            imageName: "SceneFeatureOrbitalGarden",
            title: "Orbital Garden",
            sceneNumber: "Scene 06",
            quote: "\"A living station holds the planet in the corner of your eye.\"",
            mode: "Spatial cinema",
            atmosphere: "Orbit / luminous green"
        ),
        .init(
            id: "dream-cinema",
            imageName: "SceneFeatureCinema",
            title: "Dream Cinema",
            sceneNumber: "Scene 07",
            quote: "\"Projector light turns the hall into a warm private ritual.\"",
            mode: "Classic theatre",
            atmosphere: "Velvet / brass glow"
        )
    ]
}

struct FeaturedSceneCard: View {
    var scene: FeaturedScene = .fixtures[0]
    var showsDetails: Bool = true
    var onPrevious: () -> Void = {}
    var onExpand: () -> Void = {}
    var onMore: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: Metrics.cornerRadius,
            style: .continuous
        )

        ZStack(alignment: .bottom) {
            backgroundImage
            if showsDetails {
                topMultiplyOverlay
                sceneInfoPanel
                topControls
            }
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        .overlay {
            shape.strokeBorder(DesignTokens.Surface.overlay, lineWidth: DesignTokens.Stroke.regular)
        }
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DesignPreview-FeaturedSceneCard")
        .accessibilityLabel("Featured scene card, \(scene.title)")
    }

    private var backgroundImage: some View {
        Image(scene.imageName)
            .resizable()
            .scaledToFill()
            .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
            .clipped()
    }

    private var topControls: some View {
        VStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GlassCircleIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Previous scene",
                    action: onPrevious,
                    accessibilityIdentifier: "DesignPreview-FeaturedSceneCard-button-previous"
                )
                Spacer()
                GlassCircleIconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: "Expand scene",
                    action: onExpand,
                    accessibilityIdentifier: "DesignPreview-FeaturedSceneCard-button-expand"
                )
            }
            .padding(Metrics.chromePadding)
            Spacer()
        }
    }

    private var topMultiplyOverlay: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .blendMode(.multiply)
                .mask(topMultiplyFadeMask)
                .frame(height: Metrics.topMultiplyHeight)
            Spacer(minLength: 0)
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
    }

    private var sceneInfoPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(scene.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)
                Spacer(minLength: DesignTokens.Spacing.md)
                Text(scene.sceneNumber)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(scene.quote)
                .font(.title3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Mode: \(scene.mode)")
                Text("Atmosphere: \(scene.atmosphere)")
            }
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, Metrics.infoPaddingH)
        .padding(.top, Metrics.infoPaddingTop)
        .padding(.bottom, Metrics.infoPaddingBottom)
        .frame(width: Metrics.cardWidth,
               height: Metrics.infoHeight,
               alignment: .topLeading)
        .background {
            Rectangle()
                .fill(Color.black)
                .blendMode(.multiply)
                .mask(infoMaterialFadeMask)
        }
    }

    private var infoMaterialFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(Metrics.infoFadeMinOpacity), location: 0),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.34), location: 0.08),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.52), location: 0.18),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.62), location: 0.42),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.72), location: 0.68),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.92), location: 0.88),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topMultiplyFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(Metrics.topFadeMaxOpacity), location: 0),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private enum Metrics {
        static let cardWidth: CGFloat = 500
        static let cardHeight: CGFloat = 548
        static let infoHeight: CGFloat = 188
        static let cornerRadius: CGFloat = DesignTokens.Radius.card
        static let chromePadding: CGFloat = 18
        static let infoPaddingH: CGFloat = 36
        static let infoPaddingTop: CGFloat = 34
        static let infoPaddingBottom: CGFloat = 14
        static let infoFadeMinOpacity: CGFloat = 0
        static let infoFadeMaxOpacity: CGFloat = 0.45
        static let topMultiplyHeight: CGFloat = 160
        static let topFadeMaxOpacity: CGFloat = 0.40
    }
}

struct SceneCardCarousel: View {
    var scenes: [FeaturedScene] = FeaturedScene.fixtures

    @State private var activeIndex = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var settleProgress: CGFloat = 0

    var body: some View {
        ZStack {
            if scenes.isEmpty {
                EmptyView()
            } else {
                ForEach(orderedRenderOffsets, id: \.self) { offset in
                    let visualPosition = CGFloat(offset) - dragProgress
                    let scene = scenes[wrappedIndex(activeIndex + offset)]

                    FeaturedSceneCard(
                        scene: scene,
                        showsDetails: offset == 0 && abs(dragProgress) < Metrics.detailFadeThreshold,
                        onPrevious: { move(by: -1) },
                        onExpand: {},
                        onMore: {}
                    )
                    .allowsHitTesting(offset == 0)
                    .scaleEffect(scale(for: visualPosition))
                    .rotation3DEffect(
                        .degrees(rotation(for: visualPosition)),
                        axis: (x: 0, y: 1, z: 0),
                        anchor: visualPosition < 0 ? .leading : .trailing
                    )
                    .offset(z: zOffset(for: visualPosition))
                    .offset(x: xOffset(for: visualPosition), y: yOffset(for: visualPosition))
                    .opacity(opacity(for: visualPosition))
                    .zIndex(zIndex(for: visualPosition))
                    .accessibilityHidden(offset != 0)
                }
            }
        }
        .frame(width: Metrics.stageWidth, height: Metrics.stageHeight)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(DesignTokens.AnimationToken.scene, value: activeIndex)
        .animation(DesignTokens.AnimationToken.scene, value: dragTranslation == 0)
        .accessibilityIdentifier("DesignPreview-SceneCardCarousel")
    }

    private var orderedRenderOffsets: [Int] {
        Metrics.renderOffsets.sorted {
            abs(CGFloat($0) - dragProgress) > abs(CGFloat($1) - dragProgress)
        }
    }

    private var dragProgress: CGFloat {
        guard !scenes.isEmpty else { return 0 }
        let gestureProgress = -dragTranslation / Metrics.dragDistance
        return max(-Metrics.maximumDragProgress,
                   min(Metrics.maximumDragProgress, settleProgress + gestureProgress))
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let projectedProgress = -value.predictedEndTranslation.width / Metrics.dragDistance
                let actualProgress = -value.translation.width / Metrics.dragDistance
                let shouldAdvance = projectedProgress > Metrics.snapThreshold || actualProgress > Metrics.snapThreshold
                let shouldRetreat = projectedProgress < -Metrics.snapThreshold || actualProgress < -Metrics.snapThreshold

                let targetStep = shouldAdvance ? 1 : (shouldRetreat ? -1 : 0)

                withAnimation(
                    DesignTokens.AnimationToken.scene,
                    completionCriteria: .logicallyComplete
                ) {
                    dragTranslation = 0
                    settleProgress = CGFloat(targetStep)
                } completion: {
                    if targetStep != 0 {
                        activeIndex = wrappedIndex(activeIndex + targetStep)
                    }
                    settleProgress = 0
                }
            }
    }

    private func move(by delta: Int) {
        guard !scenes.isEmpty else { return }
        withAnimation(DesignTokens.AnimationToken.scene) {
            activeIndex = wrappedIndex(activeIndex + delta)
        }
    }

    private func wrappedIndex(_ index: Int) -> Int {
        guard !scenes.isEmpty else { return 0 }
        return (index % scenes.count + scenes.count) % scenes.count
    }

    private func xOffset(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        let sign: CGFloat = position < 0 ? -1 : 1
        let compressedDistance = distance * Metrics.cardOffsetStep
            - distance * max(0, distance - 1) * Metrics.cardOffsetCompression
        return sign * compressedDistance
    }

    private func yOffset(for position: CGFloat) -> CGFloat {
        abs(position) * Metrics.sideCardYOffset
    }

    private func zOffset(for position: CGFloat) -> CGFloat {
        Metrics.centerDepthOffset - abs(position) * Metrics.sideDepthOffset
    }

    private func scale(for position: CGFloat) -> CGFloat {
        let distance = min(abs(position), 3)
        return max(Metrics.minimumScale, Metrics.centerScale - distance * Metrics.scaleStep)
    }

    private func rotation(for position: CGFloat) -> Double {
        let distance = min(abs(position), 2.5)
        let sign: Double = position < 0 ? 1 : -1
        return sign * Double(distance * Metrics.rotationStep)
    }

    private func opacity(for position: CGFloat) -> Double {
        let distance = abs(position)
        guard distance <= Metrics.visibleCardLimit else { return 0 }
        let depthOpacity = 1 - min(distance, 2) * Metrics.sideOpacityStep
        let edgeFade = 1 - max(0, distance - 2) * Metrics.edgeFadeMultiplier
        return Double(max(0, min(depthOpacity, edgeFade)))
    }

    private func zIndex(for position: CGFloat) -> Double {
        100 - Double(abs(position) * 10)
    }

    private enum Metrics {
        static let stageWidth: CGFloat = DesignTokens.SceneCarousel.stageWidth
        static let stageHeight: CGFloat = DesignTokens.SceneCarousel.stageHeight
        static let dragDistance: CGFloat = DesignTokens.SceneCarousel.dragDistance
        static let snapThreshold: CGFloat = DesignTokens.SceneCarousel.snapThreshold
        static let maximumDragProgress: CGFloat = DesignTokens.SceneCarousel.maximumDragProgress
        static let detailFadeThreshold: CGFloat = DesignTokens.SceneCarousel.detailFadeThreshold
        static let visibleCardLimit: CGFloat = DesignTokens.SceneCarousel.visibleCardLimit
        static let centerScale: CGFloat = DesignTokens.SceneCarousel.centerScale
        static let minimumScale: CGFloat = DesignTokens.SceneCarousel.minimumScale
        static let cardOffsetStep: CGFloat = DesignTokens.SceneCarousel.cardOffsetStep
        static let cardOffsetCompression: CGFloat = DesignTokens.SceneCarousel.cardOffsetCompression
        static let sideCardYOffset: CGFloat = DesignTokens.SceneCarousel.sideCardYOffset
        static let centerDepthOffset: CGFloat = DesignTokens.SceneCarousel.centerDepthOffset
        static let sideDepthOffset: CGFloat = DesignTokens.SceneCarousel.sideDepthOffset
        static let sideOpacityStep: CGFloat = DesignTokens.SceneCarousel.sideOpacityStep
        static let edgeFadeMultiplier: CGFloat = DesignTokens.SceneCarousel.edgeFadeMultiplier
        static let scaleStep: CGFloat = DesignTokens.SceneCarousel.sideScaleStep
        static let rotationStep: CGFloat = DesignTokens.SceneCarousel.rotationStepDegrees
        static let renderOffsets = [-3, -2, -1, 0, 1, 2, 3]
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

struct PathBreadcrumbMenu: View {
    let path: [String]
    var onSelectLevel: (Int) -> Void = { _ in }

    private var currentFolder: String {
        path.last ?? ""
    }

    var body: some View {
        Menu {
            ForEach(Array(path.enumerated()), id: \.offset) { index, _ in
                Button {
                    onSelectLevel(index)
                } label: {
                    Label(pathPrefix(through: index), systemImage: index == path.count - 1 ? "checkmark" : "")
                }
            }
        } label: {
            Text(currentFolder)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(currentFolder)
    }

    private func pathPrefix(through index: Int) -> String {
        path.prefix(index + 1).joined(separator: " / ")
    }
}

struct SearchInputCapsule: View {
    @Binding var text: String
    var placeholder = "Search"
    var width: CGFloat = DesignTokens.Card.gridMin
    var accessibilityIdentifier = "DesignPreview-input-search"

    @State private var isSelected = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let isActive = isSelected || isFocused

        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .hoverEffectDisabled()
                .allowsHitTesting(false)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: width, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .contentShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Surface.focusBorder.opacity(isActive ? 1 : 0),
                    lineWidth: DesignTokens.Stroke.bold
                )
                .animation(DesignTokens.AnimationToken.selection, value: isActive)
        }
        .onTapGesture {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isSelected = true
                isFocused = true
            }
        }
        .onChange(of: isFocused) { _, isFocused in
            guard !isFocused else { return }
            withAnimation(DesignTokens.AnimationToken.selection) {
                isSelected = false
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(placeholder)
    }
}

struct FilterPillBar: View {
    let filters: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(filters, id: \.self) { filter in
                Button {
                    withAnimation(DesignTokens.AnimationToken.selection) {
                        selection = filter
                    }
                } label: {
                    Text(filter)
                        .font(.body)
                        .foregroundStyle(selection == filter ? .primary : .secondary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(selection == filter ? DesignTokens.Surface.selected : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .enchronGlassPill()
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.automatic)
            }
        }
    }
}

struct SourcePaneRow: View {
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isOnline = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(isSelected ? DesignTokens.Theme.accent : .secondary)
                .frame(width: DesignTokens.Interactive.mini)

            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isOnline {
                Circle()
                    .fill(isSelected ? DesignTokens.Theme.accent : .green)
                    .frame(width: DesignTokens.Spacing.xs, height: DesignTokens.Spacing.xs)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .background(isSelected ? DesignTokens.Surface.selected : .clear, in: DesignTokens.ShapeToken.element)
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(title)
    }
}

struct PlayerProgressBar: View {
    @Namespace private var hoverNamespace
    @State private var progress: CGFloat = 0.45
    @State private var isDragging = false
    @State private var isIgnoringDrag = false
    @State private var dragStartProgress: CGFloat = 0.45
    @State private var isTimelineExpanded = false
    @State private var timelinePixelsPerSecond = DesignTokens.PrecisionTimeline.initialPixelsPerSecond

    private var trackHeight: CGFloat {
        isDragging
            ? DesignTokens.ProgressBar.trackHeight
            : DesignTokens.ProgressBar.inactiveTrackHeight
    }

    private var hoverActivationGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "progress-bar-reveal",
            in: hoverNamespace,
            behavior: .activatesGroup
        )
    }

    private var hoverRevealGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "progress-bar-reveal",
            in: hoverNamespace,
            behavior: .followsGroup
        )
    }

    var body: some View {
        let overlayWidth = DesignTokens.ProgressBar.previewWidth
        let width = max(overlayWidth - DesignTokens.ProgressBar.thumbDiameter, 0)
        let clampedProgress = min(max(progress, 0), 1)
        let thumbX = DesignTokens.ProgressBar.thumbDiameter / 2 + clampedProgress * width
        let containerWidth = currentContainerWidth
        let containerHeight = currentContainerHeight

        ZStack(alignment: .bottomLeading) {
            expandedTimelineDismissLayer(
                containerWidth: containerWidth,
                containerHeight: containerHeight
            )

            if !isTimelineExpanded {
                progressBarBody(
                    width: width,
                    clampedProgress: clampedProgress,
                    thumbX: thumbX,
                    overlayWidth: overlayWidth
                )
                .offset(x: (containerWidth - overlayWidth) / 2)
                .transition(.opacity)
            }

            expandedTimeline(containerWidth: containerWidth)
                .zIndex(2)
        }
        .frame(width: containerWidth, height: containerHeight, alignment: .bottomLeading)
        .animation(DesignTokens.AnimationToken.panelSpring, value: isTimelineExpanded)
        .accessibilityIdentifier("DesignPreview-PlayerProgressBar")
        .accessibilityLabel("Playback progress")
    }

    private var currentContainerWidth: CGFloat {
        isTimelineExpanded
            ? max(DesignTokens.ProgressBar.previewWidth, DesignTokens.PrecisionTimeline.expandedWidth)
            : DesignTokens.ProgressBar.previewWidth
    }

    private var currentContainerHeight: CGFloat {
        isTimelineExpanded
            ? DesignTokens.PrecisionTimeline.expandedHeight
            : DesignTokens.ProgressBar.hitHeight
    }

    private func progressBarBody(
        width: CGFloat,
        clampedProgress: CGFloat,
        thumbX: CGFloat,
        overlayWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            hoverCarrier(width: overlayWidth)

            progressHub(
                width: width,
                progress: clampedProgress,
                overlayWidth: overlayWidth,
                height: trackHeight
            )

            timeBubble
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2 - DesignTokens.ProgressBar.timeBubbleOffset
                )
                .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
                    effect.animation(DesignTokens.AnimationToken.selection) {
                        $0.opacity(isActive || isDragging ? 1.0 : 0.0)
                    }
                }
                .allowsHitTesting(false)

            scrubberControl(width: width)
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2
                )
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .contentShape(.interaction, Capsule())
        .gesture(dragGesture(width: width, thumbX: thumbX))
    }

    private func hoverCarrier(width: CGFloat) -> some View {
        Capsule()
            .fill(DesignTokens.ProgressBar.hoverCarrierFill)
            .frame(width: width, height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(in: hoverActivationGroup) { effect, isActive, _ in
                effect.animation(DesignTokens.AnimationToken.selection) {
                    $0.opacity(isActive ? 1.0 : DesignTokens.ProgressBar.hoverCarrierInactiveOpacity)
                }
            }
            .contentShape(.interaction, Capsule())
            .accessibilityHidden(true)
    }

    private func progressHub(
        width: CGFloat,
        progress: CGFloat,
        overlayWidth: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            progressTrack(
                width: width,
                progress: progress,
                playedColor: DesignTokens.ProgressBar.playedColor,
                unplayedColor: DesignTokens.ProgressBar.unplayedColor,
                height: height
            )
            .padding(.leading, DesignTokens.ProgressBar.thumbDiameter / 2)

            progressTrack(
                width: width,
                progress: progress,
                playedColor: DesignTokens.ProgressBar.playedHoverColor,
                unplayedColor: DesignTokens.ProgressBar.unplayedHoverColor,
                height: height
            )
            .padding(.leading, DesignTokens.ProgressBar.thumbDiameter / 2)
            .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
                effect.animation(DesignTokens.AnimationToken.selection) {
                    $0.opacity(isActive || isDragging ? 1.0 : 0.0)
                }
            }
        }
            .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
            .allowsHitTesting(false)
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
            .frame(width: DesignTokens.ProgressBar.hitHeight,
                   height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(in: hoverActivationGroup) { effect, isActive, _ in
                effect.animation(DesignTokens.AnimationToken.selection) {
                    $0.opacity(isActive || isDragging ? 1.0 : 0.0)
                }
            }
            .contentShape(Circle())
            .highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded {
                        withAnimation(DesignTokens.AnimationToken.panelSpring) {
                            isTimelineExpanded = true
                        }
                    }
            )
    }

    private func dragGesture(width: CGFloat, thumbX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isIgnoringDrag else { return }
                if !isDragging {
                    guard isThumbHit(value.startLocation, thumbX: thumbX) else {
                        isIgnoringDrag = true
                        return
                    }
                    dragStartProgress = progress
                    beginScrubbing()
                }
                isDragging = true
                progress = progress(forTranslation: value.translation.width, width: width)
            }
            .onEnded { _ in
                if isDragging {
                    endScrubbing()
                }
                isIgnoringDrag = false
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

    private func progress(forTranslation translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return progress }
        return min(max(dragStartProgress + translationX / width, 0), 1)
    }

    private func isThumbHit(_ location: CGPoint, thumbX: CGFloat) -> Bool {
        let thumbCenter = CGPoint(
            x: thumbX,
            y: DesignTokens.ProgressBar.hitHeight / 2
        )
        let hitRadius = DesignTokens.ProgressBar.hitHeight / 2
        let dx = location.x - thumbCenter.x
        let dy = location.y - thumbCenter.y
        return (dx * dx + dy * dy) <= (hitRadius * hitRadius)
    }

    @ViewBuilder
    private func expandedTimelineDismissLayer(
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        if isTimelineExpanded {
            Rectangle()
                .fill(.clear)
                .frame(width: containerWidth, height: containerHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DesignTokens.AnimationToken.panelSpring) {
                        isTimelineExpanded = false
                    }
                }
                .zIndex(1)
        }
    }

    @ViewBuilder
    private func expandedTimeline(containerWidth: CGFloat) -> some View {
        if isTimelineExpanded {
            PrecisionTimelineView(
                currentTime: timelineCurrentTime,
                pixelsPerSecond: $timelinePixelsPerSecond,
                duration: DesignTokens.PrecisionTimeline.previewDuration,
                framesPerSecond: DesignTokens.PrecisionTimeline.previewFrameRate
            )
            .frame(
                width: DesignTokens.PrecisionTimeline.expandedWidth,
                height: DesignTokens.PrecisionTimeline.expandedHeight
            )
            .scaleEffect(1.0, anchor: .bottom)
            .transition(
                .scale(
                    scale: DesignTokens.PrecisionTimeline.collapsedScale,
                    anchor: .bottom
                )
                .combined(with: .opacity)
            )
            .offset(x: (containerWidth - DesignTokens.PrecisionTimeline.expandedWidth) / 2)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
    }

    private var timelineCurrentTime: Binding<Double> {
        Binding(
            get: {
                Double(progress) * DesignTokens.PrecisionTimeline.previewDuration
            },
            set: { newValue in
                let duration = DesignTokens.PrecisionTimeline.previewDuration
                guard duration > 0 else {
                    progress = 0
                    return
                }
                let clampedTime = min(max(newValue, 0), duration)
                progress = CGFloat(clampedTime / duration)
            }
        )
    }
}

private struct PrecisionTimelineView: View {
    @Binding var currentTime: Double
    @Binding var pixelsPerSecond: CGFloat

    let duration: Double
    let framesPerSecond: Double

    @GestureState private var gestureStartPixelsPerSecond: CGFloat?
    @State private var isDraggingTimeline = false
    @State private var dragStartTime: Double = 0

    var body: some View {
        let shape = DesignTokens.ShapeToken.card

        VStack(spacing: DesignTokens.Spacing.xxs) {
            header
            rulerAndFilmStrip
        }
        .padding(.horizontal, DesignTokens.PrecisionTimeline.panelPadding)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: shape)
        .background(DesignTokens.PrecisionTimeline.panelFill, in: shape)
        .overlay {
            shape.strokeBorder(
                DesignTokens.PrecisionTimeline.panelBorder,
                lineWidth: DesignTokens.Stroke.regular
            )
        }
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.automatic)
        .contentShape(shape)
        .gesture(zoomGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline")
        .accessibilityLabel("Precision timeline")
    }

    private var header: some View {
        ZStack {
            HStack(spacing: DesignTokens.Spacing.xs) {
                frameStepButton(
                    systemName: "backward.frame",
                    label: "Previous Frame",
                    action: stepBackwardOneFrame
                )

                Text(PrecisionTimelineFormatter.timecode(currentTime, framesPerSecond: framesPerSecond))
                    .font(DesignTokens.Typography.headline)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.PrecisionTimeline.timecodeColor)

                frameStepButton(
                    systemName: "forward.frame",
                    label: "Next Frame",
                    action: stepForwardOneFrame
                )
            }
            .accessibilityIdentifier("DesignPreview-PrecisionTimeline-timecode")

            HStack(spacing: DesignTokens.Spacing.xs) {
                Spacer()
                zoomButton(systemName: "minus", label: "Zoom Out") {
                    adjustZoom(dividing: true)
                }
                zoomRail
                zoomButton(systemName: "plus", label: "Zoom In") {
                    adjustZoom(dividing: false)
                }
            }
        }
        .frame(height: DesignTokens.PrecisionTimeline.frameButtonHitSize)
    }

    private var zoomRail: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = normalizedZoom
            let thumbX = width * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignTokens.PrecisionTimeline.zoomRailFill)
                    .frame(height: DesignTokens.PrecisionTimeline.zoomRailHeight)

                Capsule()
                    .fill(DesignTokens.PrecisionTimeline.zoomRailActiveFill)
                    .frame(width: max(DesignTokens.PrecisionTimeline.zoomRailHeight, thumbX),
                           height: DesignTokens.PrecisionTimeline.zoomRailHeight)

                Circle()
                    .fill(DesignTokens.PrecisionTimeline.timecodeColor)
                    .frame(width: DesignTokens.PrecisionTimeline.zoomRailThumbSize,
                           height: DesignTokens.PrecisionTimeline.zoomRailThumbSize)
                    .position(x: thumbX, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(zoomRailGesture(width: width))
        }
        .frame(width: DesignTokens.PrecisionTimeline.zoomRailWidth,
               height: DesignTokens.PrecisionTimeline.zoomButtonSize)
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-zoom-rail")
        .accessibilityLabel("Timeline zoom")
    }

    private var rulerAndFilmStrip: some View {
        GeometryReader { proxy in
            let viewportWidth = max(proxy.size.width, 1)
            let safePixelsPerSecond = clampedPixelsPerSecond(pixelsPerSecond)
            let leadingX = viewportWidth / 2 - CGFloat(currentTime) * safePixelsPerSecond

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignTokens.PrecisionTimeline.emptyAreaFill)

                timelineRuler(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: safePixelsPerSecond
                )
                .frame(height: DesignTokens.PrecisionTimeline.rulerHeight)

                filmStrip(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: safePixelsPerSecond,
                    height: max(proxy.size.height - DesignTokens.PrecisionTimeline.rulerHeight, 1)
                )
                .offset(y: DesignTokens.PrecisionTimeline.rulerHeight)

                playhead(
                    x: viewportWidth / 2,
                    height: proxy.size.height
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.element, style: .continuous))
            .contentShape(Rectangle())
            .gesture(timelineDragGesture(pixelsPerSecond: safePixelsPerSecond))
        }
    }

    private func timelineRuler(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> some View {
        Canvas { context, size in
            let intervals = tickIntervals(pixelsPerSecond: pixelsPerSecond)
            drawTicks(
                context: &context,
                size: size,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond,
                interval: intervals.minor,
                height: DesignTokens.PrecisionTimeline.minorTickHeight,
                color: DesignTokens.PrecisionTimeline.minorTickColor,
                lineWidth: DesignTokens.Stroke.subtle
            )
            drawTicks(
                context: &context,
                size: size,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond,
                interval: intervals.major,
                height: DesignTokens.PrecisionTimeline.majorTickHeight,
                color: DesignTokens.PrecisionTimeline.majorTickColor,
                lineWidth: DesignTokens.Stroke.regular
            )
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(visibleTickTimes(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: pixelsPerSecond,
                    interval: tickIntervals(pixelsPerSecond: pixelsPerSecond).major
                ), id: \.self) { time in
                    Text(PrecisionTimelineFormatter.clock(time))
                        .font(DesignTokens.Typography.monospacedDetail)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.PrecisionTimeline.secondaryTextColor)
                        .position(
                            x: leadingX + CGFloat(time) * pixelsPerSecond,
                            y: DesignTokens.Spacing.sm
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func filmStrip(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        height: CGFloat
    ) -> some View {
        Canvas { context, size in
            drawFilmStrip(
                context: &context,
                size: size,
                viewportWidth: viewportWidth,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond
            )
        }
        .frame(height: height)
    }

    private func playhead(x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(DesignTokens.PrecisionTimeline.playheadColor)
            .frame(width: DesignTokens.PrecisionTimeline.playheadWidth)
            .overlay(alignment: .top) {
                Circle()
                    .fill(DesignTokens.PrecisionTimeline.playheadAccent)
                    .frame(
                        width: DesignTokens.Spacing.sm,
                        height: DesignTokens.Spacing.sm
                    )
                    .offset(y: -DesignTokens.Spacing.xs)
            }
            .frame(height: height)
            .position(
                x: x,
                y: height / 2
            )
            .allowsHitTesting(false)
    }

    private func frameStepButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(DesignTokens.PrecisionTimeline.timecodeColor)
                .frame(
                    width: DesignTokens.PrecisionTimeline.frameButtonSize,
                    height: DesignTokens.PrecisionTimeline.frameButtonSize
                )
                .background(DesignTokens.PrecisionTimeline.controlFill, in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.lift)
        }
        .buttonStyle(.plain)
        .frame(
            width: DesignTokens.PrecisionTimeline.frameButtonHitSize,
            height: DesignTokens.PrecisionTimeline.frameButtonHitSize
        )
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-button-\(label)")
        .accessibilityLabel(label)
    }

    private func zoomButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.PrecisionTimeline.secondaryTextColor)
                .frame(
                    width: DesignTokens.PrecisionTimeline.zoomButtonSize,
                    height: DesignTokens.PrecisionTimeline.zoomButtonSize
                )
                .background(DesignTokens.PrecisionTimeline.controlFill, in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.lift)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-button-\(label)")
        .accessibilityLabel(label)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureStartPixelsPerSecond) { _, state, _ in
                if state == nil {
                    state = pixelsPerSecond
                }
            }
            .onChanged { value in
                let start = gestureStartPixelsPerSecond ?? pixelsPerSecond
                pixelsPerSecond = clampedPixelsPerSecond(start * value.magnification)
            }
    }

    private func timelineDragGesture(pixelsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                if !isDraggingTimeline {
                    isDraggingTimeline = true
                    dragStartTime = currentTime
                }

                let delta = Double(value.translation.width / pixelsPerSecond)
                let targetTime = dragStartTime - delta
                currentTime = quantizedIfNeeded(clampedTime(targetTime))
            }
            .onEnded { _ in
                isDraggingTimeline = false
            }
    }

    private func drawTicks(
        context: inout GraphicsContext,
        size: CGSize,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        interval: Double,
        height: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        guard interval > 0, duration > 0 else { return }

        let visibleTimes = visibleTickTimes(
            viewportWidth: size.width,
            leadingX: leadingX,
            pixelsPerSecond: pixelsPerSecond,
            interval: interval
        )
        let centerY = size.height - DesignTokens.Spacing.xs

        for time in visibleTimes {
            let x = leadingX + CGFloat(time) * pixelsPerSecond
            var path = Path()
            path.move(to: CGPoint(x: x, y: centerY - height))
            path.addLine(to: CGPoint(x: x, y: centerY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func drawFilmStrip(
        context: inout GraphicsContext,
        size: CGSize,
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat
    ) {
        guard duration > 0 else { return }

        let contentWidth = CGFloat(duration) * pixelsPerSecond
        let visibleStart = max(-leadingX, 0)
        let visibleEnd = min(viewportWidth - leadingX, contentWidth)
        guard visibleStart <= visibleEnd else { return }

        let visibleFilmRect = CGRect(
            x: leadingX + visibleStart,
            y: 0,
            width: visibleEnd - visibleStart,
            height: size.height
        )
        context.fill(
            Path(visibleFilmRect),
            with: .color(DesignTokens.PrecisionTimeline.filmStripBase)
        )

        let segmentWidth = max(
            DesignTokens.PrecisionTimeline.thumbnailMinWidth,
            pixelsPerSecond * DesignTokens.PrecisionTimeline.thumbnailSecondsScale
        )
        let startIndex = max(Int(floor(-leadingX / segmentWidth)), 0)
        let endIndex = min(
            Int(ceil((viewportWidth - leadingX) / segmentWidth)),
            Int(ceil(CGFloat(duration) * pixelsPerSecond / segmentWidth))
        )
        guard startIndex <= endIndex else { return }

        for index in startIndex...endIndex {
            let x = leadingX + CGFloat(index) * segmentWidth
            let rect = CGRect(
                x: x,
                y: DesignTokens.PrecisionTimeline.filmImageInset,
                width: segmentWidth,
                height: max(size.height - DesignTokens.PrecisionTimeline.filmImageInset * 2, 1)
            )
            let palette = DesignTokens.PrecisionTimeline.thumbnailPalette
            let color = palette[index % palette.count]
            let path = Path(rect.insetBy(dx: DesignTokens.Stroke.regular, dy: DesignTokens.Stroke.subtle))

            context.fill(path, with: .color(color))
            context.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.minY + DesignTokens.Stroke.regular,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.34
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripHighlight)
            )
            context.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.midY,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.5
                )),
                with: .color(Color.black.opacity(0.12))
            )
            context.fill(
                Path(CGRect(
                    x: rect.maxX - DesignTokens.PrecisionTimeline.thumbnailSeparatorWidth,
                    y: rect.minY,
                    width: DesignTokens.PrecisionTimeline.thumbnailSeparatorWidth,
                    height: rect.height
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripSeparator)
            )
        }

        drawSprockets(
            context: &context,
            size: size,
            leadingX: leadingX,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd
        )
    }

    private func drawSprockets(
        context: inout GraphicsContext,
        size: CGSize,
        leadingX: CGFloat,
        visibleStart: CGFloat,
        visibleEnd: CGFloat
    ) {
        let holeWidth = DesignTokens.PrecisionTimeline.sprocketWidth
        let holeHeight = DesignTokens.PrecisionTimeline.sprocketHeight
        let step = holeWidth + DesignTokens.PrecisionTimeline.sprocketSpacing
        guard step > 0 else { return }

        let startIndex = Int(floor(visibleStart / step))
        let endIndex = Int(ceil(visibleEnd / step))
        let topY = DesignTokens.Spacing.xxs
        let bottomY = size.height - holeHeight - DesignTokens.Spacing.xxs

        for index in startIndex...endIndex {
            let x = leadingX + CGFloat(index) * step
            let topRect = CGRect(x: x, y: topY, width: holeWidth, height: holeHeight)
            let bottomRect = CGRect(x: x, y: bottomY, width: holeWidth, height: holeHeight)
            let topPath = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .path(in: topRect)
            let bottomPath = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .path(in: bottomRect)

            context.fill(topPath, with: .color(DesignTokens.PrecisionTimeline.sprocketFill))
            context.fill(bottomPath, with: .color(DesignTokens.PrecisionTimeline.sprocketFill))
        }
    }

    private func visibleTickTimes(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        interval: Double
    ) -> [Double] {
        guard interval > 0, pixelsPerSecond > 0 else { return [] }

        let startTime = max(0, Double((-leadingX - DesignTokens.Spacing.lg) / pixelsPerSecond))
        let endTime = min(
            duration,
            Double((viewportWidth - leadingX + DesignTokens.Spacing.lg) / pixelsPerSecond)
        )
        guard startTime <= endTime else { return [] }

        let firstTick = floor(startTime / interval) * interval
        let tickCount = Int(ceil((endTime - firstTick) / interval))

        return (0...max(tickCount, 0))
            .map { firstTick + Double($0) * interval }
            .filter { $0 >= 0 && $0 <= duration }
    }

    private func tickIntervals(pixelsPerSecond: CGFloat) -> (minor: Double, major: Double) {
        let secondsPerPoint = 1 / Double(max(pixelsPerSecond, 0.001))
        let frameInterval = 1 / max(framesPerSecond, 1)
        let intervals = niceIntervals(frameInterval: frameInterval)
        let minorTarget = secondsPerPoint * Double(DesignTokens.PrecisionTimeline.minorTickTargetSpacing)
        let majorTarget = secondsPerPoint * Double(DesignTokens.PrecisionTimeline.majorTickTargetSpacing)
        let minor = intervals.first { $0 >= minorTarget } ?? max(minorTarget, frameInterval)
        let major = intervals.first { $0 >= max(majorTarget, minor * 2) } ?? max(majorTarget, minor * 2)

        return (minor, major)
    }

    private func niceIntervals(frameInterval: Double) -> [Double] {
        [
            frameInterval,
            frameInterval * 2,
            frameInterval * 4,
            0.25,
            0.5,
            1,
            2,
            5,
            10,
            15,
            30,
            60,
            120,
            300,
            600,
            1_200,
            1_800,
            3_600
        ]
    }

    private var zoomLabel: String {
        let secondsInView = Double(availableTimelineWidth / max(clampedPixelsPerSecond(pixelsPerSecond), 0.001))
        return "\(PrecisionTimelineFormatter.clock(secondsInView)) visible"
    }

    private var availableTimelineWidth: CGFloat {
        DesignTokens.PrecisionTimeline.expandedWidth - DesignTokens.PrecisionTimeline.panelPadding * 2
    }

    private func adjustZoom(dividing: Bool) {
        let ratio = DesignTokens.PrecisionTimeline.zoomStepRatio
        let next = dividing ? pixelsPerSecond / ratio : pixelsPerSecond * ratio
        withAnimation(DesignTokens.AnimationToken.selection) {
            pixelsPerSecond = clampedPixelsPerSecond(next)
        }
    }

    private var normalizedZoom: CGFloat {
        let minValue = log(Double(DesignTokens.PrecisionTimeline.minPixelsPerSecond))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let current = log(Double(clampedPixelsPerSecond(pixelsPerSecond)))
        guard maxValue > minValue else { return 0 }
        return CGFloat(min(max((current - minValue) / (maxValue - minValue), 0), 1))
    }

    private func zoomRailGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let normalized = min(max(value.location.x / max(width, 1), 0), 1)
                pixelsPerSecond = zoomValue(forNormalized: normalized)
            }
    }

    private func zoomValue(forNormalized normalized: CGFloat) -> CGFloat {
        let minValue = log(Double(DesignTokens.PrecisionTimeline.minPixelsPerSecond))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let value = minValue + (maxValue - minValue) * Double(normalized)
        return clampedPixelsPerSecond(CGFloat(exp(value)))
    }

    private func stepBackwardOneFrame() {
        currentTime = clampedTime(currentTime - frameDuration)
    }

    private func stepForwardOneFrame() {
        currentTime = clampedTime(currentTime + frameDuration)
    }

    private var frameDuration: Double {
        1 / max(framesPerSecond, 1)
    }

    private func quantizedIfNeeded(_ time: Double) -> Double {
        let pointsPerFrame = clampedPixelsPerSecond(pixelsPerSecond) * CGFloat(frameDuration)
        guard pointsPerFrame >= DesignTokens.Spacing.xs else { return time }
        return (time / frameDuration).rounded() * frameDuration
    }

    private func clampedTime(_ time: Double) -> Double {
        min(max(time, 0), duration)
    }

    private func clampedPixelsPerSecond(_ value: CGFloat) -> CGFloat {
        min(
            max(value, DesignTokens.PrecisionTimeline.minPixelsPerSecond),
            DesignTokens.PrecisionTimeline.maxPixelsPerSecond
        )
    }
}

private enum PrecisionTimelineFormatter {
    static func clock(_ seconds: Double) -> String {
        let clamped = max(seconds, 0)
        let totalSeconds = Int(clamped.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func timecode(_ seconds: Double, framesPerSecond: Double) -> String {
        let frameRate = max(Int(framesPerSecond.rounded()), 1)
        let totalFrames = max(Int((seconds * Double(frameRate)).rounded()), 0)
        let framesPerHour = frameRate * 3_600
        let framesPerMinute = frameRate * 60
        let hours = totalFrames / framesPerHour
        let minutes = (totalFrames % framesPerHour) / framesPerMinute
        let secs = (totalFrames % framesPerMinute) / frameRate
        let frame = totalFrames % frameRate

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frame)
    }
}

struct PlayerProgressStrip: View {
    var body: some View {
        PlayerProgressBar()
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
