import SwiftUI

struct FeaturedEnvironment: Identifiable {
    let environment: SpatialSceneDomain.CinemaEnvironment
    let imageName: String
    let title: String
    let environmentNumber: String
    let quote: String
    let mode: String
    let atmosphere: String

    var id: String { environment.rawValue }

    static let catalog: [FeaturedEnvironment] = [
        .init(
            environment: .darkTheatre,
            imageName: "SceneFeatureCinema",
            title: "Dark Theatre",
            environmentNumber: "Environment 01",
            quote: "\"A focused private theatre with the world held outside.\"",
            mode: "Classic theatre",
            atmosphere: "Dark / quiet"
        ),
        .init(
            environment: .starryNight,
            imageName: "SceneFeatureOrbitalGarden",
            title: "Starry Night",
            environmentNumber: "Environment 02",
            quote: "\"A quiet screen beneath an open night sky.\"",
            mode: "Open-air cinema",
            atmosphere: "Night / starlight"
        ),
        .init(
            environment: .sunsetNature,
            imageName: "SceneFeatureDesert",
            title: "Sunset Nature",
            environmentNumber: "Environment 03",
            quote: "\"Warm horizon light surrounds a calm viewing space.\"",
            mode: "Nature cinema",
            atmosphere: "Sunset / warm air"
        )
    ]
}

struct EnvironmentCard: View {
    var environment: FeaturedEnvironment = .catalog[0]
    var detailVisibility: CGFloat = 1
    var atmosphericFade: CGFloat = 0
    var onReturn: () -> Void = {}
    var onExpand: () -> Void = {}
    var onMore: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: Metrics.cornerRadius,
            style: .continuous
        )

        ZStack(alignment: .bottom) {
            backgroundImage
            topMultiplyOverlay
            environmentInfoPanel
            topControls
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        .overlay {
            shape.strokeBorder(DesignTokens.Surface.overlay, lineWidth: DesignTokens.Stroke.regular)
        }
        .enchronHoverContentShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DesignPreview-EnvironmentCard")
        .accessibilityLabel("Featured environment card, \(environment.title)")
    }

    private var clampedDetailVisibility: CGFloat {
        max(0, min(1, detailVisibility))
    }

    private var clampedAtmosphericFade: CGFloat {
        max(0, min(1, atmosphericFade))
    }

    private var backgroundImage: some View {
        Image(environment.imageName)
            .resizable()
            .scaledToFill()
            .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
            .saturation(Double(1 - clampedAtmosphericFade * Metrics.atmosphericDesaturation))
            .contrast(Double(1 - clampedAtmosphericFade * Metrics.atmosphericContrastReduction))
            .blur(radius: clampedAtmosphericFade * Metrics.atmosphericBlurRadius)
            .clipped()
    }

    private var topControls: some View {
        VStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GlassCircleIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Return to window",
                    action: onReturn,
                    accessibilityIdentifier: "DesignPreview-EnvironmentCard-button-return"
                )
                Spacer()
                GlassCircleIconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: "Expand environment",
                    action: onExpand,
                    accessibilityIdentifier: "DesignPreview-EnvironmentCard-button-expand"
                )
            }
            .padding(Metrics.chromePadding)
            Spacer()
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .opacity(Double(clampedDetailVisibility))
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
        .opacity(Double(clampedDetailVisibility))
    }

    private var environmentInfoPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(environment.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)
                Spacer(minLength: DesignTokens.Spacing.md)
                Text(environment.environmentNumber)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(environment.quote)
                .font(.title3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Mode: \(environment.mode)")
                Text("Atmosphere: \(environment.atmosphere)")
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
        .opacity(Double(clampedDetailVisibility))
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
        static let atmosphericContrastReduction: CGFloat = 0.68
        static let atmosphericDesaturation: CGFloat = 0.38
        static let atmosphericBlurRadius: CGFloat = 2.6
    }
}

struct EnvironmentCarouselRenderSlot: Identifiable, Equatable {
    struct ID: Hashable {
        let environmentIndex: Int
        let cycle: Int
    }

    let id: ID
    let environmentIndex: Int
    let visualPosition: CGFloat
}

enum EnvironmentCarouselLayout {
    static func renderSlots(
        environmentCount: Int,
        scrollPosition: CGFloat,
        maximumDistance: CGFloat
    ) -> [EnvironmentCarouselRenderSlot] {
        guard environmentCount > 0 else { return [] }
        if environmentCount == 1 {
            return [
                EnvironmentCarouselRenderSlot(
                    id: .init(environmentIndex: 0, cycle: 0),
                    environmentIndex: 0,
                    visualPosition: 0
                )
            ]
        }

        let count = CGFloat(environmentCount)

        return (0..<environmentCount).flatMap { index -> [EnvironmentCarouselRenderSlot] in
            let basePosition = CGFloat(index) - scrollPosition
            let minimumCycle = Int(ceil((-maximumDistance - basePosition) / count))
            let maximumCycle = Int(floor((maximumDistance - basePosition) / count))
            guard minimumCycle <= maximumCycle else { return [] }

            return (minimumCycle...maximumCycle).map { cycle in
                EnvironmentCarouselRenderSlot(
                    id: .init(environmentIndex: index, cycle: cycle),
                    environmentIndex: index,
                    visualPosition: basePosition + CGFloat(cycle) * count
                )
            }
        }
    }
}

struct EnvironmentCardCarousel: View {
    var environments: [FeaturedEnvironment] = FeaturedEnvironment.catalog
    var onReturn: () -> Void = {}
    /// Center-card expand (enter immersive). Forwarded from the focused card's
    /// expand control; defaults to no-op for Canvas review (ENV-18).
    var onExpand: (FeaturedEnvironment) -> Void = { _ in }

    @State private var scrollPosition: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var isSettling = false
    @State private var detailsVisible = true
    @State private var motionGeneration = 0
    @State private var detailRevealTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if environments.isEmpty {
                EmptyView()
            } else {
                ForEach(renderItems) { item in
                    EnvironmentCard(
                        environment: item.environment,
                        detailVisibility: interactionDetailVisibility(for: item.visualPosition),
                        atmosphericFade: atmosphericFade(for: item.visualPosition),
                        onReturn: onReturn,
                        onExpand: { onExpand(item.environment) },
                        onMore: {}
                    )
                    .allowsHitTesting(abs(item.visualPosition) < Metrics.centerHitTestingDistance)
                    .opacity(Double(cardOpacity(for: item.visualPosition)))
                    .enchronSpatialOffset(z: zOffset(for: item.visualPosition))
                    .offset(x: xOffset(for: item.visualPosition), y: yOffset(for: item.visualPosition))
                    .zIndex(zIndex(for: item.visualPosition))
                    .accessibilityHidden(abs(item.visualPosition) >= Metrics.centerHitTestingDistance)
                }
            }
        }
        .frame(width: Metrics.stageWidth, height: Metrics.stageHeight)
        .enchronSpatialFrame(depth: Metrics.stageDepth)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityIdentifier("DesignPreview-EnvironmentCardCarousel")
    }

    private var renderItems: [RenderItem] {
        EnvironmentCarouselLayout.renderSlots(
            environmentCount: environments.count,
            scrollPosition: currentScrollPosition,
            maximumDistance: activeRenderCardDistance
        ).map { slot in
            return RenderItem(
                id: slot.id,
                visualPosition: slot.visualPosition,
                environment: environments[slot.environmentIndex]
            )
        }
    }

    private var activeRenderCardDistance: CGFloat {
        isDragging || isSettling ? Metrics.motionRenderCardDistance : Metrics.stableRenderCardDistance
    }

    private var currentScrollPosition: CGFloat {
        guard !environments.isEmpty else { return 0 }
        let gestureProgress = -dragTranslation / Metrics.dragDistance
        return scrollPosition + gestureProgress
    }

    private var interactionDetailScale: CGFloat {
        detailsVisible && !isDragging ? 1 : 0
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                if !isDragging {
                    motionGeneration += 1
                    detailRevealTask?.cancel()
                    isDragging = true
                    isSettling = false
                    detailsVisible = false
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let actualProgress = -value.translation.width / Metrics.dragDistance
                let projectedProgress = -value.predictedEndTranslation.width / Metrics.dragDistance
                let actualPosition = scrollPosition + actualProgress
                let projectedPosition = scrollPosition + projectedProgress
                let targetPosition = targetScrollPosition(
                    actualPosition: actualPosition,
                    projectedPosition: projectedPosition
                )
                let targetStepDistance = abs(targetPosition - scrollPosition)
                let generation = motionGeneration

                isDragging = false
                isSettling = true
                scheduleDetailReveal(for: generation, stepDistance: targetStepDistance)
                withAnimation(
                    DesignTokens.AnimationToken.sceneCarouselSettle,
                    completionCriteria: .logicallyComplete
                ) {
                    dragTranslation = 0
                    scrollPosition = targetPosition
                } completion: {
                    guard generation == motionGeneration else {
                        return
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollPosition = normalizedScrollPosition(targetPosition)
                        isSettling = false
                    }
                }
            }
    }

    private func scheduleDetailReveal(for generation: Int, stepDistance: CGFloat) {
        detailRevealTask?.cancel()
        detailRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: detailRevealDelay(for: stepDistance))
            guard !Task.isCancelled,
                  generation == motionGeneration,
                  !isDragging
            else {
                return
            }

            withAnimation(DesignTokens.AnimationToken.fadeIn) {
                detailsVisible = true
            }
        }
    }

    private func detailRevealDelay(for stepDistance: CGFloat) -> UInt64 {
        Metrics.detailRevealDelayNanoseconds
            + UInt64(max(0, stepDistance.rounded(.down))) * Metrics.detailRevealDelayPerStepNanoseconds
    }

    private func normalizedScrollPosition(_ position: CGFloat) -> CGFloat {
        guard !environments.isEmpty else { return 0 }
        let environmentCount = CGFloat(environments.count)
        let remainder = position.truncatingRemainder(dividingBy: environmentCount)
        return remainder >= 0 ? remainder : remainder + environmentCount
    }

    private func targetScrollPosition(actualPosition: CGFloat, projectedPosition: CGFloat) -> CGFloat {
        let actualDelta = actualPosition - scrollPosition
        let rawProjectedDelta = projectedPosition - scrollPosition
        let projectedDelta = clamped(
            rawProjectedDelta,
            lowerBound: actualDelta - Metrics.maximumPredictedStepLead,
            upperBound: actualDelta + Metrics.maximumPredictedStepLead
        )
        let dominantDelta = abs(projectedDelta) > abs(actualDelta) ? projectedDelta : actualDelta
        let boundedDelta = clamped(
            dominantDelta,
            lowerBound: -Metrics.maximumStepPerGesture,
            upperBound: Metrics.maximumStepPerGesture
        )
        let roundedDelta = boundedDelta.rounded()

        if roundedDelta == 0, abs(boundedDelta) > Metrics.snapThreshold {
            return scrollPosition + (boundedDelta > 0 ? 1 : -1)
        }

        return scrollPosition + roundedDelta
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(lowerBound, min(upperBound, value))
    }

    private func xOffset(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        let sign: CGFloat = position < 0 ? -1 : 1
        let baseOffset = distance <= 1
            ? distance * Metrics.centerCardGap
            : Metrics.centerCardGap + (distance - 1) * Metrics.outerCardGap
        return sign * (baseOffset + edgeExitProgress(for: distance) * Metrics.edgeSlideOutDistance)
    }

    private func yOffset(for position: CGFloat) -> CGFloat {
        abs(position) * Metrics.sideCardYOffset
    }

    private func zOffset(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        let baseOffset = Metrics.centerDepthOffset - distance * Metrics.sideDepthOffset
        let edgeExitOffset = edgeExitProgress(for: distance) * Metrics.edgeDepthRetreat
        return baseOffset - edgeExitOffset
    }

    private func cardOpacity(for position: CGFloat) -> CGFloat {
        let distance = abs(position)

        if distance <= Metrics.fullOpacityDistance {
            return 1
        } else if distance <= Metrics.firstSideOpacityDistance {
            return interpolatedOpacity(
                from: 1,
                to: Metrics.firstSideOpacity,
                distance: distance,
                start: Metrics.fullOpacityDistance,
                end: Metrics.firstSideOpacityDistance
            )
        } else if distance <= Metrics.fullFadeDistance {
            return interpolatedOpacity(
                from: Metrics.firstSideOpacity,
                to: 0,
                distance: distance,
                start: Metrics.firstSideOpacityDistance,
                end: Metrics.fullFadeDistance
            )
        }

        return 0
    }

    private func interpolatedOpacity(
        from startOpacity: CGFloat,
        to endOpacity: CGFloat,
        distance: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGFloat {
        let range = end - start
        guard range > 0 else { return endOpacity }
        let progress = clamped((distance - start) / range, lowerBound: 0, upperBound: 1)
        let easedProgress = progress * progress * (3 - 2 * progress)
        return startOpacity + (endOpacity - startOpacity) * easedProgress
    }

    private func interactionDetailVisibility(for position: CGFloat) -> CGFloat {
        detailVisibility(for: position) * interactionDetailScale
    }

    private func detailVisibility(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        guard distance < Metrics.detailRevealStart else { return 0 }

        let revealRange = Metrics.detailRevealStart - Metrics.detailRevealComplete
        guard revealRange > 0 else { return 1 }

        return max(0, min(1, (Metrics.detailRevealStart - distance) / revealRange))
    }

    private func atmosphericFade(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        guard distance > Metrics.atmosphericFadeStart else { return 0 }

        let fadeRange = Metrics.atmosphericFadeEnd - Metrics.atmosphericFadeStart
        guard fadeRange > 0 else { return Metrics.atmosphericFadeMaxOpacity }

        let progress = max(0, min(1, (distance - Metrics.atmosphericFadeStart) / fadeRange))
        let edgeBoost = edgeExitProgress(for: distance) * Metrics.edgeAtmosphericBoost
        return min(1, progress * Metrics.atmosphericFadeMaxOpacity + edgeBoost)
    }

    private func edgeExitProgress(for distance: CGFloat) -> CGFloat {
        guard distance > Metrics.edgeExitStart else { return 0 }

        let exitRange = Metrics.edgeExitEnd - Metrics.edgeExitStart
        guard exitRange > 0 else { return 1 }

        let rawProgress = max(0, min(1, (distance - Metrics.edgeExitStart) / exitRange))
        return rawProgress * rawProgress
    }

    private func zIndex(for position: CGFloat) -> Double {
        100 - Double(abs(position) * 10)
    }

    private enum Metrics {
        static let stageWidth: CGFloat = DesignTokens.EnvironmentCarousel.stageWidth
        static let stageHeight: CGFloat = DesignTokens.EnvironmentCarousel.stageHeight
        static let stageDepth: CGFloat = DesignTokens.EnvironmentCarousel.stageDepth
        static let dragDistance: CGFloat = DesignTokens.EnvironmentCarousel.dragDistance
        static let snapThreshold: CGFloat = DesignTokens.EnvironmentCarousel.snapThreshold
        static let maximumPredictedStepLead: CGFloat = DesignTokens.EnvironmentCarousel.maximumPredictedStepLead
        static let maximumStepPerGesture: CGFloat = DesignTokens.EnvironmentCarousel.maximumStepPerGesture
        static let detailRevealDelayNanoseconds = DesignTokens.EnvironmentCarousel.detailRevealDelayNanoseconds
        static let detailRevealDelayPerStepNanoseconds =
            DesignTokens.EnvironmentCarousel.detailRevealDelayPerStepNanoseconds
        static let centerHitTestingDistance: CGFloat = 0.12
        static let stableRenderCardDistance: CGFloat = 1.55
        static let motionRenderCardDistance: CGFloat = 2.18
        static let fullOpacityDistance: CGFloat = 0.10
        static let firstSideOpacityDistance: CGFloat = 1.00
        static let fullFadeDistance: CGFloat = 2.18
        static let firstSideOpacity: CGFloat = 0.85
        static let edgeExitStart: CGFloat = 1.35
        static let edgeExitEnd: CGFloat = 2.18
        static let edgeSlideOutDistance: CGFloat = 300
        static let edgeDepthRetreat: CGFloat = 42
        static let edgeAtmosphericBoost: CGFloat = 0.42
        static let centerCardGap: CGFloat = DesignTokens.EnvironmentCarousel.centerCardGap
        static let outerCardGap: CGFloat = DesignTokens.EnvironmentCarousel.outerCardGap
        static let sideCardYOffset: CGFloat = DesignTokens.EnvironmentCarousel.sideCardYOffset
        static let centerDepthOffset: CGFloat = DesignTokens.EnvironmentCarousel.centerDepthOffset
        static let sideDepthOffset: CGFloat = DesignTokens.EnvironmentCarousel.sideDepthOffset
        static let atmosphericFadeStart: CGFloat = DesignTokens.EnvironmentCarousel.atmosphericFadeStart
        static let atmosphericFadeEnd: CGFloat = DesignTokens.EnvironmentCarousel.atmosphericFadeEnd
        static let atmosphericFadeMaxOpacity: CGFloat = DesignTokens.EnvironmentCarousel.atmosphericFadeMaxOpacity
        static let detailRevealStart: CGFloat = DesignTokens.EnvironmentCarousel.detailRevealStart
        static let detailRevealComplete: CGFloat = DesignTokens.EnvironmentCarousel.detailRevealComplete
    }

    private struct RenderItem: Identifiable {
        let id: EnvironmentCarouselRenderSlot.ID
        let visualPosition: CGFloat
        let environment: FeaturedEnvironment
    }
}

// MARK: - Row items

// MARK: - File List Group

/// A file-browsing list group that shares the common row shell while owning
/// media-specific icons, metadata and gaze behavior.
