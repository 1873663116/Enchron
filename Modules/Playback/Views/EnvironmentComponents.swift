import DesignSystem
import SwiftUI

public struct FeaturedEnvironment: Identifiable {
    public let environment: SpatialSceneDomain.CinemaEnvironment
    public let lightImageName: String
    public let darkImageName: String
    public let title: String
    public let environmentNumber: String
    public let quote: String
    public let mode: String
    public let atmosphere: String

    public var id: String { environment.rawValue }

    static func catalogEntry(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> FeaturedEnvironment? {
        catalog.first { $0.environment == environment }
    }

    func imageName(for effect: SpatialSceneDomain.EnvironmentEffect) -> String {
        switch effect {
        case .light: lightImageName
        case .dark: darkImageName
        }
    }

    public static let defaultEnvironmentThumbnailName = "EnvironmentQuietRoom"

    public static let catalog: [FeaturedEnvironment] = [
        .init(
            environment: .ocean,
            lightImageName: "EnvironmentOcean",
            darkImageName: "EnvironmentOceanDark",
            title: String(localized: "Ocean"),
            environmentNumber: String(localized: "Environment 01"),
            quote: String(localized: "\"Open water under a slow sky, the screen mirrored in the swell.\""),
            mode: String(localized: "Open water"),
            atmosphere: String(localized: "Light Mode / Dark Mode")
        ),
        .init(
            environment: .placeholderRed,
            lightImageName: "EnvironmentPlaceholderRed",
            darkImageName: "EnvironmentPlaceholderRedDark",
            title: "Red",
            environmentNumber: "Environment 02",
            quote: "\"A solid red placeholder for a future environment.\"",
            mode: "Placeholder",
            atmosphere: "Light Mode / Dark Mode"
        ),
        .init(
            environment: .placeholderGreen,
            lightImageName: "EnvironmentPlaceholderGreen",
            darkImageName: "EnvironmentPlaceholderGreenDark",
            title: "Green",
            environmentNumber: "Environment 03",
            quote: "\"A solid green placeholder for a future environment.\"",
            mode: "Placeholder",
            atmosphere: "Light Mode / Dark Mode"
        ),
        .init(
            environment: .placeholderBlue,
            lightImageName: "EnvironmentPlaceholderBlue",
            darkImageName: "EnvironmentPlaceholderBlueDark",
            title: "Blue",
            environmentNumber: "Environment 04",
            quote: "\"A solid blue placeholder for a future environment.\"",
            mode: "Placeholder",
            atmosphere: "Light Mode / Dark Mode"
        )
    ]
}

public struct EnvironmentCard: View {
    var environment: FeaturedEnvironment = .catalog[0]
    var effect: SpatialSceneDomain.EnvironmentEffect = .light
    var isEnvironmentActive = false
    var detailVisibility: CGFloat = 1
    var atmosphericFade: CGFloat = 0
    var onEffectChange: (SpatialSceneDomain.EnvironmentEffect) -> Void = { _ in }
    var onExpand: () -> Void = {}
    var isDefault = false
    var onSetDefault: () -> Void = {}

    public var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.EnvironmentCard.cornerRadius,
            style: .continuous
        )

        ZStack(alignment: .bottom) {
            backgroundImage
            topMultiplyOverlay
            environmentInfoPanel
            topControls
        }
        .frame(
            width: DesignTokens.EnvironmentCard.width,
            height: DesignTokens.EnvironmentCard.height
        )
        .clipShape(shape)
        .enchronGlassBackground(in: shape)
        .overlay {
            shape.strokeBorder(DesignTokens.Surface.overlay, lineWidth: DesignTokens.Stroke.regular)
        }
        .enchronHoverContentShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("EnvironmentCard-card")
        .accessibilityLabel("Featured environment card, \(environment.title)")
    }

    private var clampedDetailVisibility: CGFloat {
        max(0, min(1, detailVisibility))
    }

    private var clampedAtmosphericFade: CGFloat {
        max(0, min(1, atmosphericFade))
    }

    private var backgroundImage: some View {
        Image(environment.imageName(for: effect))
            .resizable()
            .scaledToFill()
            .frame(
                width: DesignTokens.EnvironmentCard.width,
                height: DesignTokens.EnvironmentCard.height
            )
            .saturation(
                Double(1 - clampedAtmosphericFade * DesignTokens.EnvironmentCard.atmosphericDesaturation)
            )
            .contrast(
                Double(1 - clampedAtmosphericFade * DesignTokens.EnvironmentCard.atmosphericContrastReduction)
            )
            .blur(
                radius: clampedAtmosphericFade * DesignTokens.EnvironmentCard.atmosphericBlurRadius
            )
            .clipped()
    }

    private var topControls: some View {
        VStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                if environment.environment.supportsDarkAppearance {
                    AppearanceModeButton(
                        isActive: effect == .dark,
                        accessibilityLabel: effect == .light
                            ? "Switch environment to Dark Mode"
                            : "Switch environment to Light Mode",
                        action: {
                            onEffectChange(effect == .light ? .dark : .light)
                        },
                        accessibilityIdentifier:
                            "EnvironmentCard-effect-\(environment.environment.rawValue)"
                    )
                }
                Spacer()
                CircleIconButton.expandCollapse(
                    isExpanded: isEnvironmentActive,
                    accessibilityLabel: isEnvironmentActive
                        ? "Close environment"
                        : "Open environment",
                    action: onExpand,
                    accessibilityIdentifier:
                        "EnvironmentCard-button-environment-\(environment.environment.rawValue)"
                )
            }
            .padding(DesignTokens.EnvironmentCard.chromePadding)
            Spacer()
        }
        .frame(
            width: DesignTokens.EnvironmentCard.width,
            height: DesignTokens.EnvironmentCard.height
        )
        .opacity(Double(clampedDetailVisibility))
    }

    private var topMultiplyOverlay: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .blendMode(.multiply)
                .mask(topMultiplyFadeMask)
                .frame(height: DesignTokens.EnvironmentCard.topMultiplyHeight)
            Spacer(minLength: 0)
        }
        .frame(
            width: DesignTokens.EnvironmentCard.width,
            height: DesignTokens.EnvironmentCard.height
        )
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
                    .foregroundStyle(
                        .white.opacity(DesignTokens.EnvironmentCard.secondaryTextOpacity)
                    )
            }

            Text(environment.quote)
                .font(.title3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Mode: \(environment.mode)")
                    Text("Atmosphere: \(environment.atmosphere)")
                }
                .foregroundStyle(
                    .white.opacity(DesignTokens.EnvironmentCard.secondaryTextOpacity)
                )
                Spacer(minLength: 0)
                Button(action: onSetDefault) {
                    Label(isDefault ? "Default" : "Set as default",
                          systemImage: isDefault ? "checkmark.circle.fill" : "circle")
                }
                .fixedSize()
                .disabled(isDefault)
                .accessibilityIdentifier("EnvironmentCard-default-\(environment.id)")
            }
            .font(DesignTokens.Typography.metadata)
        }
        .padding(.horizontal, DesignTokens.EnvironmentCard.informationPaddingH)
        .padding(.top, DesignTokens.EnvironmentCard.informationPaddingTop)
        .padding(.bottom, DesignTokens.EnvironmentCard.informationPaddingBottom)
        .frame(width: DesignTokens.EnvironmentCard.width,
               height: DesignTokens.EnvironmentCard.informationHeight,
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
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMinOpacity), location: 0),
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMaxOpacity * 0.34), location: 0.08),
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMaxOpacity * 0.52), location: 0.18),
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMaxOpacity * 0.62), location: 0.42),
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMaxOpacity * 0.72), location: 0.68),
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMaxOpacity * 0.92), location: 0.88),
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.informationFadeMaxOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topMultiplyFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(DesignTokens.EnvironmentCard.topFadeMaxOpacity), location: 0),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public init(
        environment: FeaturedEnvironment = .catalog[0],
        effect: SpatialSceneDomain.EnvironmentEffect = .light,
        isEnvironmentActive: Bool = false,
        detailVisibility: CGFloat = 1,
        atmosphericFade: CGFloat = 0,
        onEffectChange: @escaping (SpatialSceneDomain.EnvironmentEffect) -> Void = { _ in },
        onExpand: @escaping () -> Void = {},
        isDefault: Bool = false,
        onSetDefault: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.effect = effect
        self.isEnvironmentActive = isEnvironmentActive
        self.detailVisibility = detailVisibility
        self.atmosphericFade = atmosphericFade
        self.onEffectChange = onEffectChange
        self.onExpand = onExpand
        self.isDefault = isDefault
        self.onSetDefault = onSetDefault
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
    static func initialPosition(
        environments: [FeaturedEnvironment],
        defaultEnvironment: SpatialSceneDomain.CinemaEnvironment
    ) -> CGFloat {
        CGFloat(environments.firstIndex { $0.environment == defaultEnvironment } ?? 0)
    }

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
    var activeEnvironment: SpatialSceneDomain.CinemaEnvironment?
    var defaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .ocean
    var isPresented = true
    var onSetDefault: (SpatialSceneDomain.CinemaEnvironment) -> Void = { _ in }
    var defaultEffect: SpatialSceneDomain.EnvironmentEffect = .inactiveFallback
    var onEffectChange:
        (FeaturedEnvironment, SpatialSceneDomain.EnvironmentEffect) -> Void = { _, _ in }
    var onExpand:
        (FeaturedEnvironment, SpatialSceneDomain.EnvironmentEffect) -> Void = { _, _ in }

    @State private var scrollPosition: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var isSettling = false
    @State private var detailsVisible = true
    @State private var motionGeneration = 0
    @State private var detailRevealTask: Task<Void, Never>?
    @State private var selectedEffects:
        [SpatialSceneDomain.CinemaEnvironment: SpatialSceneDomain.EnvironmentEffect] = [:]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("EnvironmentCard-carousel")
                .accessibilityLabel("Environment carousel")

            if environments.isEmpty {
                EmptyView()
            } else {
                ForEach(renderItems) { item in
                    EnvironmentCard(
                        environment: item.environment,
                        effect: selectedEffect(for: item.environment),
                        isEnvironmentActive:
                            activeEnvironment == item.environment.environment,
                        detailVisibility: interactionDetailVisibility(for: item.visualPosition),
                        atmosphericFade: atmosphericFade(for: item.visualPosition),
                        onEffectChange: {
                            selectedEffects[item.environment.environment] = $0
                            onEffectChange(item.environment, $0)
                        },
                        onExpand: {
                            onExpand(
                                item.environment,
                                selectedEffect(for: item.environment)
                            )
                        },
                        isDefault: item.environment.environment == defaultEnvironment,
                        onSetDefault: { onSetDefault(item.environment.environment) }
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
        .onAppear(perform: centerDefaultEnvironment)
        .onChange(of: isPresented) { _, presented in
            if presented { centerDefaultEnvironment() }
        }
    }

    private func centerDefaultEnvironment() {
        motionGeneration += 1
        detailRevealTask?.cancel()
        dragTranslation = 0
        isDragging = false
        isSettling = false
        detailsVisible = true
        scrollPosition = EnvironmentCarouselLayout.initialPosition(
            environments: environments, defaultEnvironment: defaultEnvironment
        )
    }

    private func selectedEffect(
        for environment: FeaturedEnvironment
    ) -> SpatialSceneDomain.EnvironmentEffect {
        selectedEffects[environment.environment] ?? defaultEffect
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
        DesignTokens.EnvironmentCarousel.zIndexBase
            - Double(abs(position)) * DesignTokens.EnvironmentCarousel.zIndexDistanceStep
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
        static let centerHitTestingDistance: CGFloat = DesignTokens.EnvironmentCarousel.centerHitTestingDistance
        static let stableRenderCardDistance: CGFloat = DesignTokens.EnvironmentCarousel.stableRenderCardDistance
        static let motionRenderCardDistance: CGFloat = DesignTokens.EnvironmentCarousel.motionRenderCardDistance
        static let fullOpacityDistance: CGFloat = DesignTokens.EnvironmentCarousel.fullOpacityDistance
        static let firstSideOpacityDistance: CGFloat = DesignTokens.EnvironmentCarousel.firstSideOpacityDistance
        static let fullFadeDistance: CGFloat = DesignTokens.EnvironmentCarousel.fullFadeDistance
        static let firstSideOpacity: CGFloat = DesignTokens.EnvironmentCarousel.firstSideOpacity
        static let edgeExitStart: CGFloat = DesignTokens.EnvironmentCarousel.edgeExitStart
        static let edgeExitEnd: CGFloat = DesignTokens.EnvironmentCarousel.edgeExitEnd
        static let edgeSlideOutDistance: CGFloat = DesignTokens.EnvironmentCarousel.edgeSlideOutDistance
        static let edgeDepthRetreat: CGFloat = DesignTokens.EnvironmentCarousel.edgeDepthRetreat
        static let edgeAtmosphericBoost: CGFloat = DesignTokens.EnvironmentCarousel.edgeAtmosphericBoost
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
