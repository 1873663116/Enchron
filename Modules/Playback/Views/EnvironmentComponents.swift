import DesignSystem
import SwiftUI
import UIKit

public struct FeaturedEnvironment: Identifiable {
    public let environment: SpatialSceneDomain.CinemaEnvironment
    public let lightImageName: String
    public let darkImageName: String
    public let title: String

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

    public static let quietRoomThumbnailName = "EnvironmentQuietRoom"

    public static let catalog: [FeaturedEnvironment] = [
        .init(
            environment: .ocean,
            lightImageName: "EnvironmentOcean",
            darkImageName: "EnvironmentOceanDark",
            title: String(localized: "Ocean")
        ),
        .init(
            environment: .tidal,
            lightImageName: "EnvironmentTidal",
            darkImageName: "EnvironmentTidalDark",
            title: String(localized: "Tidal")
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
    var controlsEnabled = true
    var isDefault = false
    var onSetDefault: () -> Void = {}
    var scale: CGFloat = 1

    private var metrics: DesignTokens.EnvironmentCard.Metrics {
        DesignTokens.EnvironmentCard.metrics(scale: scale)
    }

    public var body: some View {
        let shape = DesignTokens.ShapeToken.card

        ZStack(alignment: .bottom) {
            backgroundImage
            topReadabilityScrim
            environmentInfoPanel
            topControls
        }
        .frame(
            width: metrics.width,
            height: metrics.height
        )
        .clipShape(shape)
        .enchronCardSurface(in: shape)
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
        ZStack {
            thumbnail
                .id(thumbnailName)
                .transition(.opacity)
        }
        .animation(DesignTokens.AnimationToken.controlsTransition, value: thumbnailName)
    }

    private var thumbnailName: String {
        environment.imageName(for: effect)
    }

    private var thumbnail: some View {
        Image(thumbnailName)
            .resizable()
            .scaledToFill()
            .frame(
                width: metrics.width,
                height: metrics.height
            )
            .saturation(
                Double(1 - clampedAtmosphericFade * DesignTokens.EnvironmentCard.atmosphericDesaturation)
            )
            .contrast(
                Double(1 - clampedAtmosphericFade * DesignTokens.EnvironmentCard.atmosphericContrastReduction)
            )
            .blur(
                radius: clampedAtmosphericFade * metrics.atmosphericBlurRadius
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
                            ? String(localized: "Dark Mode")
                            : String(localized: "Light Mode"),
                        action: {
                            onEffectChange(effect == .light ? .dark : .light)
                        },
                        accessibilityIdentifier:
                            "EnvironmentCard-effect-\(environment.environment.rawValue)"
                    )
                    .disabled(controlsEnabled == false)
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
                .disabled(controlsEnabled == false)
            }
            .padding(metrics.chromePadding)
            Spacer()
        }
        .frame(
            width: metrics.width,
            height: metrics.height
        )
        .opacity(Double(clampedDetailVisibility))
        .allowsHitTesting(clampedDetailVisibility == 1)
        .accessibilityHidden(clampedDetailVisibility < 1)
    }

    private var topReadabilityScrim: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DesignTokens.Surface.textScrimMaterial)
                .mask(topReadabilityMask)
                .frame(height: metrics.topScrimHeight)
            Spacer(minLength: 0)
        }
        .frame(
            width: metrics.width,
            height: metrics.height
        )
        .opacity(Double(clampedDetailVisibility))
        .allowsHitTesting(clampedDetailVisibility == 1)
        .accessibilityHidden(clampedDetailVisibility < 1)
    }

    private var environmentInfoPanel: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(environment.title)
                .font(DesignTokens.Typography.title)
                .foregroundStyle(.white)
            Spacer(minLength: DesignTokens.Spacing.md)
            Button(action: onSetDefault) {
                Label(isDefault ? "Default" : "Set as default",
                      systemImage: isDefault ? "checkmark.circle.fill" : "circle")
            }
            .font(DesignTokens.Typography.metadata)
            .fixedSize()
            .disabled(isDefault)
            .accessibilityIdentifier("EnvironmentCard-default-\(environment.id)")
        }
        .padding(.horizontal, metrics.informationPaddingH)
        .padding(.bottom, metrics.informationPaddingBottom)
        .frame(width: metrics.width,
               height: metrics.informationHeight,
               alignment: .bottomLeading)
        .background {
            Rectangle()
                .fill(DesignTokens.Surface.textScrimMaterial)
                .mask(infoMaterialFadeMask)
        }
        .opacity(Double(clampedDetailVisibility))
        .allowsHitTesting(clampedDetailVisibility == 1)
        .accessibilityHidden(clampedDetailVisibility < 1)
    }

    private var infoMaterialFadeMask: some View {
        LinearGradient(
            stops: readabilityScrimStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topReadabilityMask: some View {
        LinearGradient(
            stops: readabilityScrimStops,
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var readabilityScrimStops: [Gradient.Stop] {
        DesignTokens.Surface.textScrimStops(
            leadFraction: 1 - Double(DesignTokens.Surface.textScrimPlateauFraction)
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
        controlsEnabled: Bool = true,
        isDefault: Bool = false,
        onSetDefault: @escaping () -> Void = {},
        scale: CGFloat = 1
    ) {
        self.environment = environment
        self.effect = effect
        self.isEnvironmentActive = isEnvironmentActive
        self.detailVisibility = detailVisibility
        self.atmosphericFade = atmosphericFade
        self.onEffectChange = onEffectChange
        self.onExpand = onExpand
        self.controlsEnabled = controlsEnabled
        self.isDefault = isDefault
        self.onSetDefault = onSetDefault
        self.scale = scale
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
        cardDefaultEnvironment: SpatialSceneDomain.CinemaEnvironment
    ) -> CGFloat {
        CGFloat(environments.firstIndex { $0.environment == cardDefaultEnvironment } ?? 0)
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
#if DEBUG
    @Environment(PlaybackSessionModel.self) private var appModel
#endif
    var environments: [FeaturedEnvironment] = FeaturedEnvironment.catalog
    var activeEnvironment: SpatialSceneDomain.CinemaEnvironment?
    var cardDefaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .ocean
    var isPresented = true
    var onSetDefault: (SpatialSceneDomain.CinemaEnvironment) -> Void = { _ in }
    var effect: SpatialSceneDomain.EnvironmentEffect = .inactiveFallback
    var controlsEnabled = true
    var onCenterChange: (SpatialSceneDomain.CinemaEnvironment) -> Void = { _ in }
    var onEffectChange: (SpatialSceneDomain.EnvironmentEffect) -> Void = { _ in }
    var onToggle: () -> Void = {}
    var availableWidth: CGFloat = DesignTokens.EnvironmentCarousel.referenceWindowWidth

    @State private var scrollPosition: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var isSettling = false
    @State private var detailsVisible = true
    @State private var motionGeneration = 0
    @State private var detailRevealTask: Task<Void, Never>?

    private var compositionScale: CGFloat {
        availableWidth / DesignTokens.EnvironmentCarousel.referenceWindowWidth
    }

    private var metrics: DesignTokens.EnvironmentCarousel.Metrics {
        DesignTokens.EnvironmentCarousel.metrics(scale: compositionScale)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("EnvironmentCard-carousel")
                .accessibilityLabel("Environment carousel")
                .accessibilityValue(renderItems.min { abs($0.visualPosition) < abs($1.visualPosition) }?.environment.id ?? "")

            if environments.isEmpty {
                EmptyView()
            } else {
                ForEach(renderItems) { item in
                    EnvironmentCard(
                        environment: item.environment,
                        effect: effect,
                        isEnvironmentActive: activeEnvironment != nil,
                        detailVisibility: interactionDetailVisibility(for: item.visualPosition),
                        atmosphericFade: atmosphericFade(for: item.visualPosition),
                        onEffectChange: onEffectChange,
                        onExpand: onToggle,
                        controlsEnabled: controlsEnabled,
                        isDefault: item.environment.environment == cardDefaultEnvironment,
                        onSetDefault: { onSetDefault(item.environment.environment) },
                        scale: compositionScale
                    )
                    .allowsHitTesting(abs(item.visualPosition) < Metrics.centerHitTestingDistance)
                    .opacity(Double(cardOpacity(for: item.visualPosition)))
                    .enchronSpatialOffset(z: zOffset(for: item.visualPosition))
                    .offset(x: xOffset(for: item.visualPosition))
                    .zIndex(zIndex(for: item.visualPosition))
                    .accessibilityHidden(abs(item.visualPosition) >= Metrics.centerHitTestingDistance)
                }
            }
        }
        .frame(width: metrics.stageWidth, height: metrics.stageHeight)
        .contentShape(Rectangle())
        .simultaneousGesture(dragGesture)
        .onAppear(perform: centerDefaultEnvironment)
        .onChange(of: prefetchEnvironment, initial: true) { _, environment in
            guard activeEnvironment == nil else { return }
            EnvironmentSceneMapping.prefetch(environment.map { [$0] } ?? [])
        }
        .onDisappear {
            if activeEnvironment == nil { EnvironmentSceneMapping.prefetch([]) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            EnvironmentSceneMapping.prefetch([])
        }
        .onChange(of: centeredEnvironment, initial: true) { _, environment in
            onCenterChange(environment)
        }
        .onChange(of: isPresented) { _, presented in
            if presented { centerDefaultEnvironment() }
        }
    }

    private var centeredEnvironment: SpatialSceneDomain.CinemaEnvironment {
        renderItems.min { abs($0.visualPosition) < abs($1.visualPosition) }?
            .environment.environment ?? cardDefaultEnvironment
    }

    private var prefetchEnvironment: SpatialSceneDomain.CinemaEnvironment? {
        guard isPresented, activeEnvironment == nil, !isDragging, !isSettling,
              !environments.isEmpty else { return nil }
        let index = Int(currentScrollPosition.rounded())
        let wrapped = ((index % environments.count) + environments.count) % environments.count
        return environments[wrapped].environment
    }

    private func centerDefaultEnvironment() {
        motionGeneration += 1
        detailRevealTask?.cancel()
        dragTranslation = 0
        isDragging = false
        isSettling = false
        detailsVisible = true
        scrollPosition = EnvironmentCarouselLayout.initialPosition(
            environments: environments, cardDefaultEnvironment: cardDefaultEnvironment
        )
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
        let gestureProgress = -dragTranslation / metrics.dragDistance
        return scrollPosition + gestureProgress
    }

    private var interactionDetailScale: CGFloat {
        detailsVisible && !isDragging ? 1 : 0
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                if !isDragging {
#if DEBUG
                    appModel.recordSurfaceInputProbe("environmentHome drag=began", retention: .evidence)
#endif
                    motionGeneration += 1
                    detailRevealTask?.cancel()
                    isDragging = true
                    isSettling = false
                    detailsVisible = false
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
#if DEBUG
                appModel.recordSurfaceInputProbe("environmentHome drag=ended translation=\(value.translation.width)", retention: .evidence)
#endif
                let actualProgress = -value.translation.width / metrics.dragDistance
                let projectedProgress = -value.predictedEndTranslation.width / metrics.dragDistance
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
            ? distance * metrics.centerCardGap
            : metrics.centerCardGap + (distance - 1) * metrics.outerCardGap
        return sign * (baseOffset + edgeExitProgress(for: distance) * metrics.edgeSlideOutDistance)
    }

    private func zOffset(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        let baseOffset = metrics.centerDepthOffset - distance * metrics.sideDepthOffset
        let edgeExitOffset = edgeExitProgress(for: distance) * metrics.edgeDepthRetreat
        return max(metrics.windowFrontClearance, baseOffset - edgeExitOffset)
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
        static let edgeAtmosphericBoost: CGFloat = DesignTokens.EnvironmentCarousel.edgeAtmosphericBoost
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
