import SwiftUI
import PlaybackPresentation

struct SenseZoneVolumeRoot: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        EnvironmentCardCarousel(
            activeEnvironment: appModel.environmentContext.environment,
            defaultEffect: appModel.currentEnvironmentEffect,
            onEffectChange: updateEnvironmentEffect,
            onExpand: toggleEnvironment
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SenseZone-VolumeRoot")
        .accessibilityLabel("SenseZone environments")
        .background { SpatialPlatformEffectExecutor() }
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
