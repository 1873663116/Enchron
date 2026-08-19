import SwiftUI
import PlaybackPresentation

struct SenseZoneVolumeRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityPrefersCrossFadeTransitions)
    private var accessibilityPrefersCrossFadeTransitions
    @Environment(\.scenePhase) private var scenePhase

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
        .animation(revealAnimation, value: revealCompleted)
        .onAppear {
            appModel.receiveSpatialPlatformResult(.environmentCardAppeared)
            sceneLifetimeIsOpen = true
            revealIfNeeded()
        }
        .onDisappear {
            appModel.receiveSpatialPlatformResult(.environmentCardDisappeared)
        }
        .onChange(of: scenePhase, initial: true) { _, scenePhase in
            switch scenePhase {
            case .active, .inactive:
                appModel.receiveSpatialPlatformResult(.environmentCardAppeared)
            case .background:
                appModel.receiveSpatialPlatformResult(.environmentCardDisappeared)
            @unknown default:
                break
            }
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
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentCard effect delivered environment=\(featured.environment.rawValue)"
                + " effect=\(effect.rawValue)",
            retention: .evidence
        )
#endif
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
#if DEBUG
            appModel.recordSurfaceInputProbe(
                "environmentCard toggle delivered environment=\(featured.environment.rawValue)"
                    + " effect=\(effect.rawValue)",
                retention: .evidence
            )
#endif
            if appModel.environmentContext.environment == featured.environment {
                try appModel.requestEnvironmentPreviewDismissal()
            } else {
                guard appModel.immersiveSpaceResidency == .closed else { return }
                try appModel.requestEnvironmentPreview(
                    environment: featured.environment,
                    effect: featured.environment.isScenic ? effect : nil
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
