import SwiftUI
import PlaybackPresentation

struct SenseZoneVolumeRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityPrefersCrossFadeTransitions)
    private var accessibilityPrefersCrossFadeTransitions

    @State private var revealCompleted = false
    @State private var sceneLifetimeIsOpen = false

    var body: some View {
        EnvironmentCardCarousel(
            activeEnvironment: appModel.environmentContext.environment,
            defaultEffect: appModel.currentEnvironmentEffect,
            onEffectChange: updateEnvironmentEffect,
            onExpand: toggleEnvironment
        )
        .opacity(revealCompleted ? 1 : 0)
        .scaleEffect(revealCompleted ? 1 : revealInitialScale)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SenseZone-VolumeRoot")
        .accessibilityLabel("SenseZone environments")
        .background { SpatialPlatformEffectExecutor() }
        .animation(revealAnimation, value: revealCompleted)
        .onAppear {
            sceneLifetimeIsOpen = true
            revealIfNeeded()
        }
        .onChange(of: appModel.environmentCardResidency) { _, residency in
            switch residency {
            case .open, .opening:
                sceneLifetimeIsOpen = true
            case .closed where sceneLifetimeIsOpen:
                // The Window scene owns this lifetime boundary. Resetting only
                // after its closed fact lets a future scene lifetime reveal
                // again without replaying while the singleton Volume is merely
                // focused.
                sceneLifetimeIsOpen = false
                revealCompleted = false
            case .closed:
                break
            }
        }
    }

    private var revealInitialScale: CGFloat {
        accessibilityReduceMotion || accessibilityPrefersCrossFadeTransitions
            ? 1
            : EnvironmentCardRevealMotion.initialScale
    }

    private var revealAnimation: Animation {
        if accessibilityPrefersCrossFadeTransitions || accessibilityReduceMotion {
            return .easeOut(duration: EnvironmentCardRevealMotion.crossFadeDuration)
        }
        return .easeOut(duration: EnvironmentCardRevealMotion.standardDuration)
    }

    private func revealIfNeeded() {
        guard !revealCompleted else { return }
        withAnimation(revealAnimation) {
            revealCompleted = true
        }
    }

    private func updateEnvironmentEffect(
        _ featured: FeaturedEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        guard appModel.environmentContext.environment == featured.environment else {
            return
        }
        appModel.setActiveEnvironmentEffect(effect)
    }

    private func toggleEnvironment(
        _ featured: FeaturedEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        do {
            if appModel.environmentContext.environment == featured.environment {
                try appModel.requestEnvironmentPreviewDismissal()
            } else {
                guard appModel.immersiveSpaceResidency == .closed else { return }
                try appModel.requestEnvironmentPreview(
                    environment: featured.environment,
                    effect: effect
                )
            }
        } catch {
            return
        }
    }
}

enum EnvironmentCardRevealMotion {
    static let initialScale: CGFloat = 0.985
    static let standardDuration = 0.26
    static let crossFadeDuration = 0.12
}
