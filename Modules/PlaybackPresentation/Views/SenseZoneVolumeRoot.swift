import SwiftUI

struct SenseZoneVolumeRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        EnvironmentCardCarousel(
            onReturn: returnToMain,
            onExpand: enterImmersive
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SenseZone-VolumeRoot")
        .accessibilityLabel("SenseZone environments")
    }

    private func returnToMain() {
        guard !appModel.isEnvironmentTransitionInFlight else { return }
        appModel.isEnvironmentTransitionInFlight = true
        dismissWindow(id: AppModel.senseZoneVolumeID)
        appModel.isEnvironmentTransitionInFlight = false
    }

    private func enterImmersive(_ featured: FeaturedEnvironment) {
        appModel.currentCinemaEnvironment = featured.environment
        appModel.isEnvironmentImmersiveActive = true
        appModel.requestImmersiveSpace()
    }
}
