import RealityKitScripting
import SwiftUI

@main
struct XrPlayerApp: App {
    @State private var application: EnchronApplication
    @State private var immersionStyle: ImmersionStyle = .full

    init() {
        do {
            try RKS.initialize()
        } catch {
            assertionFailure("RealityKitScripting initialization failed: \(error)")
        }
        _application = State(initialValue: EnchronApplication())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .enchronEnvironment(application)
        }
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentSize)

        WindowGroup(id: "playerControls") {
            SpatialPlaybackControlsRoot()
                .enchronEnvironment(application)
        }
        .defaultSize(width: 760, height: 220)
        .windowResizability(.contentSize)

        WindowGroup(id: AppModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .environment(application.appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.4, height: 0.9, depth: 0.8, in: .meters)

        ImmersiveSpace(id: application.appModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .environment(application.appModel)
                .environment(application.playbackRuntime)
                .onAppear {
                    application.appModel.immersiveSpaceState = .open
                    Task { await application.appModel.loadScreenPosition() }
                }
                .onDisappear {
                    if application.playbackRuntime.attachedPresentation != .window {
                        application.playbackRuntime.detach()
                    }
                    application.appModel.immersiveSpaceState = .closed
                    if let transition = application.appModel.presentationTransition,
                       transition.targetPresentation != .window {
                        application.appModel.rollbackPlaybackPresentation(transition.id)
                    }
                    application.appModel.isEnvironmentImmersiveActive = false
                }
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
        .onChange(of: application.appModel.isFullImmersion) { _, full in
            immersionStyle = full ? .full : .mixed
        }
    }
}
