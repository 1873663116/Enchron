import RealityKitScripting
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

@main
struct EnchronApp: App {
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
        Window("Enchron", id: "main") {
            MainView()
                .enchronEnvironment(application)
        }
        .defaultSize(
            width: WindowPlaybackLayout.fallback.defaultSize.width,
            height: WindowPlaybackLayout.fallback.defaultSize.height
        )
        // Playback supplies the visible video surface. Browser pages restore
        // the system-shaped glass explicitly inside MainView.
        .windowStyle(.plain)
        .windowResizability(.contentSize)

        Window("Player Controls", id: "playerControls") {
            SpatialPlaybackControlsRoot()
                .enchronEnvironment(application)
        }
        .defaultSize(width: 760, height: 220)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("Environment", id: AppModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .enchronEnvironment(application)
                .onAppear {
                    application.appModel.receiveSpatialPlatformResult(
                        .environmentCardAppeared
                    )
                }
                .onDisappear {
                    application.appModel.receiveSpatialPlatformResult(
                        .environmentCardDisappeared
                    )
                }
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.4, height: 0.9, depth: 0.8, in: .meters)

        ImmersiveSpace(id: application.appModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .environment(application.appModel)
                .environment(application.playbackRuntime)
                .onAppear {
                    application.spatialPlatformEffectCoordinator
                        .recordImmersiveSpaceResidency(.open)
                    application.appModel.receiveSpatialPlatformResult(
                        .immersiveSpaceAppeared
                    )
                    Task { await application.appModel.loadScreenPosition() }
                }
                .onDisappear {
                    application.spatialPlatformEffectCoordinator
                        .recordImmersiveSpaceResidency(.closed)
                    let playbackContext = application.playbackRuntime.activeSessionID.map {
                        SpatialPlaybackTransitionContext(
                            mediaSessionID: $0,
                            wasPlaying: application.playbackRuntime.productLifecycle == .playing
                        )
                    }
                    if application.playbackRuntime.attachedPresentation != .window {
                        application.playbackRuntime.detach()
                    }
                    application.appModel.receiveSpatialPlatformResult(
                        .immersiveSpaceDisappeared(playbackContext)
                    )
                }
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
        .onChange(of: application.appModel.platformPrefersFullImmersion) { _, full in
            immersionStyle = full ? .full : .mixed
        }
    }
}
