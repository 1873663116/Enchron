import SwiftUI

/// Production SenseZone volume content: the polished `EnvironmentCardCarousel`
/// (7 featured environments) hosted in a volumetric `WindowGroup`. Replaces the
/// old `SceneSelectorView` sheet as the Environments destination (ENV-13/14/16/17).
///
/// The center card's expand control enters the immersive space through the single
/// canonical entry point (`AppModel.requestImmersiveSpace` → `MainView`), which in
/// this round loads the procedural dome; the RCP `world` swap is ADR-0008 (ENV-18).
///
/// Deviation from the design's "close main window on entry": the volume coexists
/// with the main window so `MainView` stays alive to service the immersive-space
/// request (the architecture's single immersive entry point lives there).
struct SenseZoneVolumeRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        EnvironmentCardCarousel(
            onReturn: returnToMain,
            onExpand: { _ in enterImmersive() }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SenseZone-VolumeRoot")
        .accessibilityLabel("SenseZone environments")
    }

    // ENV-14 / ENV-15: close the volume; the main window (kept alive) resumes its
    // prior tab. The in-flight guard absorbs repeated return taps mid-transition.
    private func returnToMain() {
        guard !appModel.isEnvironmentTransitionInFlight else { return }
        appModel.isEnvironmentTransitionInFlight = true
        dismissWindow(id: AppModel.senseZoneVolumeID)
        appModel.isEnvironmentTransitionInFlight = false
    }

    // ENV-18: route through the canonical immersive entry point.
    private func enterImmersive() {
        appModel.requestImmersiveSpace()
    }
}
