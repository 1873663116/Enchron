import EnvironmentSceneContract
import RealityKitScripting
import Playback
import SwiftUI
import UIKit

@main
struct EnchronApp: App {
    @UIApplicationDelegateAdaptor(EnchronAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var mainScenePhase
    @State private var application: EnchronApplication
    @State private var immersionStyle: ImmersionStyle = .progressive(
        SpatialImmersiveSpacePolicy.progressiveImmersionRange
    )

    init() {
        ScriptingRuntime.setup(inputOptions: .all.subtracting(.ar))
        _application = State(initialValue: EnchronApplication())
    }

    var body: some Scene {
        WindowGroup(
            "Enchron",
            id: "main"
        ) {
            WindowSceneGate(window: .main) {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.environment[
                    "ENCHRON_SAMPLE_BUFFER_ACOUSTIC_CALIBRATION"
                ] == "1" {
                    SampleBufferAcousticCalibrationView()
                } else if ProcessInfo.processInfo.environment[
                    "ENCHRON_ACOUSTIC_CALIBRATION"
                ] == "1" {
                    AcousticCalibrationView()
                } else {
                    MainView()
                }
#else
                MainView()
#endif
            }
            .background {
                SpatialPlatformEffectExecutor(windowIdentity: .main)
            }
            }
            .onChange(of: mainScenePhase) { previous, current in
                SurfaceInputProbes.record("mainScenePhase \(previous) -> \(current)")
                application.handleScenePhaseTransition(to: current)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: EnchronAppDelegate.sceneSessionsDiscarded
                )
            ) { notification in
                guard let identifiers = notification.object as? Set<String> else {
                    return
                }
                application.spatialPlatformEffectCoordinator
                    .sceneSessionsWereDiscarded(identifiers)
            }
            .enchronEnvironment(application)
            .onAppear {
                SurfaceInputProbes.record("mainWindowScene appeared")
                application.spatialPlatformEffectCoordinator
                    .recordWindowResidency(.open, for: .main)
                Task { @MainActor in
                    await Task.yield()
                    application.spatialPlatformEffectCoordinator
                        .reconcileImmersiveSpaceResidency()
                }
            }
            .onDisappear {
                SurfaceInputProbes.record("mainWindowScene disappeared")
                application.spatialPlatformEffectCoordinator
                    .recordWindowResidency(.closed, for: .main)
            }
        }
        .defaultSize(
            width: BrowserWindowLayout.defaultSize.width,
            height: BrowserWindowLayout.defaultSize.height
        )
        .windowStyle(.plain)
        .persistentSystemOverlays(
            BrowserWindowVisibility(
                window: .main,
                playbackResidency: application.spatialPlatformEffectCoordinator
                    .playbackResidency
            ).systemOverlays
        )
        .windowResizability(.contentSize)

        WindowGroup(
            "Player",
            id: SpatialPlatformWindowIdentity.player.rawValue
        ) {
            WindowSceneGate(window: .player) {
                PlayerView()
                    .playbackDisplayCriteriaHost(application.playbackRuntime.displayCriteria)
                    .background {
                        SpatialPlatformEffectExecutor(windowIdentity: .player)
                    }
                    .preferredSurroundingsEffect(
                        application.settingsViewModel.preferences.surroundingsDimmingEnabled
                            ? .ultraDark
                            : nil
                    )
            }
            .enchronEnvironment(application)
        }
        .windowStyle(.plain)
        .defaultSize(
            width: BrowserWindowLayout.defaultSize.width,
            height: BrowserWindowLayout.defaultSize.height
        )
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

#if DEBUG
        WindowGroup("Blackout Probe", id: "blackoutProbe") {
            Color.clear.frame(width: 760, height: 220)
        }
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
#endif

        Window("Environment", id: PlaybackSessionModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .enchronEnvironment(application)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.4, height: 0.9, depth: 0.8, in: .meters)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        ImmersiveSpace(id: application.playbackSessionModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .playbackDisplayCriteriaHost(application.playbackRuntime.displayCriteria, immersive: true)
                .background {
                    SpatialPlatformEffectExecutor()
                }
                .preferredSurroundingsEffect(immersiveSurroundingsEffect)
                .enchronEnvironment(application)
                .onImmersionChange { _, newImmersion in
                    application.playbackSessionModel.recordImmersionAmount(newImmersion.amount)
                }
                .onAppear {
                    application.playbackSessionModel.recordSurfaceInputProbe(
                        "immersiveSpaceAppeared"
                            + " presentation=\(application.playbackSessionModel.playbackPresentation.rawValue)"
                            + " transition=\(application.playbackSessionModel.presentationTransition?.targetPresentation.rawValue ?? "none")"
                    )
                    application.spatialPlatformEffectCoordinator
                        .recordImmersiveSpaceResidency(.open)
                    application.playbackSessionModel.receiveSpatialPlatformResult(
                        .immersiveSpaceAppeared
                    )
                    Task { await application.playbackSessionModel.loadScreenPosition() }
                }
                .onDisappear {
                    application.playbackSessionModel.recordSurfaceInputProbe(
                        "immersiveSpaceDisappeared"
                            + " presentation=\(application.playbackSessionModel.playbackPresentation.rawValue)"
                            + " transition=\(application.playbackSessionModel.presentationTransition?.targetPresentation.rawValue ?? "none")"
                            + " attached=\(application.playbackRuntime.attachedPresentation?.rawValue ?? "none")"
                            + " lifecycle=\(application.playbackRuntime.productLifecycle)"
                            + " stage=\(application.playbackSessionModel.spatialPlaybackSurfacePreparationStage)"
                    )
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
                    application.playbackSessionModel.receiveSpatialPlatformResult(
                        .immersiveSpaceDisappeared(playbackContext)
                    )
                }
        }
        .immersionStyle(selection: $immersionStyle, in: .progressive)
        .onChange(of: application.playbackSessionModel.immersiveSpaceStyleRevision) { _, _ in
            immersionStyle = .progressive(
                SpatialImmersiveSpacePolicy.progressiveImmersionRange,
                initialAmount: application.playbackSessionModel.immersiveSpaceOpeningInitialAmount
            )
        }
    }

    private var immersiveSurroundingsEffect: SurroundingsEffect? {
        guard application.settingsViewModel.preferences.surroundingsDimmingEnabled,
              application.playbackSessionModel.playbackPresentation.usesImmersiveSpace
        else { return nil }
        let geometry = EnvironmentSceneMapping.geometry(
            for: application.playbackSessionModel.currentCinemaEnvironment
        )
        return geometry.dimsSurroundings ? .ultraDark : nil
    }
}

private final class EnchronAppDelegate: NSObject, UIApplicationDelegate {
    static let sceneSessionsDiscarded = Notification.Name(
        "app.enchron.sceneSessionsDiscarded"
    )

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        NotificationCenter.default.post(
            name: Self.sceneSessionsDiscarded,
            object: Set(sceneSessions.map(\.persistentIdentifier))
        )
    }
}

private struct WindowSceneGate<Content: View>: View {
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    @State private var ownSessionIdentifier: String?
    @State private var ownWindowScene: UIWindowScene?
    private let window: SpatialPlatformWindowIdentity
    private let content: () -> Content

    init(
        window: SpatialPlatformWindowIdentity,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.window = window
        self.content = content
    }

    private var isOrphaned: Bool {
        SpatialPlatformWindowScenePolicy.isOrphaned(
            ownSessionIdentifier: ownSessionIdentifier,
            liveSessionIdentifier: spatialPlatformEffectCoordinator
                .liveWindowSessionIdentifiers[window]
        )
    }

    private var browserVisibility: BrowserWindowVisibility {
        BrowserWindowVisibility(
            window: window,
            playbackResidency: spatialPlatformEffectCoordinator.playbackResidency
        )
    }

    var body: some View {
        Group {
            if isOrphaned {
                Color.clear
            } else {
                content()
            }
        }
        .browserWindowContentVisibility(browserVisibility)
        .windowSceneReporting { windowScene in
            ownWindowScene = windowScene
            if let identifier = windowScene?.session.persistentIdentifier {
                ownSessionIdentifier = identifier
            }
            spatialPlatformEffectCoordinator.recordWindowScene(windowScene, for: window)
        }
        .onChange(of: isOrphaned) { _, orphaned in
            guard orphaned else { return }
            SurfaceInputProbes.record(
                "windowScene orphaned window=\(window.rawValue)"
                    + " session=\(ownSessionIdentifier ?? "none")",
                retention: .evidence
            )
            guard let session = ownWindowScene?.session else { return }
            let windowName = window.rawValue
            UIApplication.shared.requestSceneSessionDestruction(
                session,
                options: nil
            ) { error in
                SurfaceInputProbes.record(
                    "windowScene orphanDestroyFailed window=\(windowName)"
                        + " error=\(error.localizedDescription)",
                    retention: .evidence
                )
            }
        }
        .onAppear {
            guard isOrphaned == false else { return }
            spatialPlatformEffectCoordinator
                .recordWindowResidency(.open, for: window)
        }
        .onDisappear {
            guard isOrphaned == false else { return }
            spatialPlatformEffectCoordinator
                .recordWindowResidency(.closed, for: window)
        }
    }
}
