import DesignSystem
import Emby
import Foundation
import MediaSource
import OSLog
import Playback
import SwiftUI

public struct MainView: View {
    private let logger = Logger(subsystem: "app.enchron", category: "MainView")
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(EmbySessionViewModel.self) private var embySession
    @Environment(EmbyHomeViewModel.self) private var embyHome
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    @Environment(ConnectionSecurityPrompt.self) private var connectionSecurityPrompt

    public init() {}

    public var body: some View {
        browserPrimaryContent
        .browserWindowGeometry { windowScene in
            spatialPlatformEffectCoordinator.recordWindowScene(windowScene, for: .main)
        }
        .enchronWindowGlassBackground(.always)
        .onAppear {
            playbackRuntime.onPlaybackEnded = {
                let showControls = playbackLauncher.handlePlaybackEnded {
                    playbackSession.showControls = true
                }
                if showControls {
                    playbackSession.showControls = true
                }
            }
        }
        .onChange(of: playbackRuntime.residency, initial: true) { _, residency in
            spatialPlatformEffectCoordinator.applyPlaybackResidency(residency)
        }
        .alert(
            Text(connectionSecurityPrompt.question?.title ?? ""),
            isPresented: Binding(
                get: { connectionSecurityPrompt.question != nil },
                set: { if $0 == false { connectionSecurityPrompt.resolve(approved: false) } }
            )
        ) {
            switch connectionSecurityPrompt.question {
            case .cleartextCredentials:
                Button("仍然连接", role: .destructive) {
                    connectionSecurityPrompt.resolve(approved: true)
                }
                .accessibilityIdentifier("FileBrowsing-CleartextExposure-proceed")
                Button("取消", role: .cancel) {
                    connectionSecurityPrompt.resolve(approved: false)
                }
                .accessibilityIdentifier("FileBrowsing-CleartextExposure-cancel")
            case .unverifiedCertificate, .none:
                Button("信任", role: .destructive) {
                    connectionSecurityPrompt.resolve(approved: true)
                }
                .accessibilityIdentifier("FileBrowsing-CertificateTrust-trust")
                Button("取消", role: .cancel) {
                    connectionSecurityPrompt.resolve(approved: false)
                }
                .accessibilityIdentifier("FileBrowsing-CertificateTrust-cancel")
            }
        } message: {
            if let question = connectionSecurityPrompt.question {
                Text(question.message)
            }
        }
    }

    private func launchEmbySelection(_ selection: EmbyPlaybackSelection) async {
        do {
            let request = try await embySession.playbackRequest(for: selection)
            SurfaceInputProbes.record("openRequestForwarded")
            playbackLauncher.requestPlayback(request)
        } catch {
            logger.error(
                "Emby playback request failed error=\(error.localizedDescription, privacy: .public)"
            )
            SurfaceInputProbes.record("emby playback request failed error=\(error)", retention: .evidence)
            playbackRuntime.setUserVisibleIssue(.mediaRequestFailed)
        }
    }

    private var browserPrimaryContent: some View {
        ZStack {
            browser
        }
        .alert(
            "Resume Playback?",
            isPresented: Binding(
                get: { playbackLauncher.pendingResumeDecision != nil },
                set: { if $0 == false { playbackLauncher.cancelPendingResumeDecision() } }
            ),
            presenting: playbackLauncher.pendingResumeDecision
        ) { _ in
            Button("Resume") {
#if DEBUG
                playbackSession.recordSurfaceInputProbe(
                    "reachability resume decision delivered action=resume",
                    retention: .evidence
                )
#endif
                playbackLauncher.resumePendingPlayback()
            }
            .accessibilityIdentifier("PlayerUI-resumeDecision-primary")
            Button("Play from Start") {
#if DEBUG
                playbackSession.recordSurfaceInputProbe(
                    "reachability resume decision delivered action=startOver",
                    retention: .evidence
                )
#endif
                playbackLauncher.startPendingPlaybackFromBeginning()
            }
            .accessibilityIdentifier("PlayerUI-resumeDecision-secondary")
        } message: { decision in
            Text("Continue from \(PlaybackTimeFormatter.clock(decision.seconds)) or start from the beginning.")
        }
        .playbackIssueAlert(at: .mediaLibrary)
    }

    private var browser: some View {
        TabView(selection: browserTabSelection) {
            Tab("Files", systemImage: "folder", value: AppModel.NavigationTab.files) {
                FilesScreenHost()
                    .enchronScreenAppearance()
                    .toolbarVisibility(browserTabBarVisibility, for: .tabBar)
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-files")

            Tab("Emby", systemImage: "play.tv.fill", value: AppModel.NavigationTab.emby) {
                EmbyScreen { selectionResult in
                    guard let selection = try? selectionResult.get() else {
                        playbackRuntime.setUserVisibleIssue(.mediaRequestFailed)
                        return
                    }
                    playbackLauncher.decideResume(fromSeconds: selection.resumeCandidateSeconds) { resume in
                        Task {
                            await launchEmbySelection(
                                selection.replacingStartAction(resume ? .resume : .fromBeginning)
                            )
                        }
                    }
                }
                .enchronScreenAppearance()
                .toolbarVisibility(browserTabBarVisibility, for: .tabBar)
            }
            .accessibilityIdentifier("Emby-Navigation-Tab")

            Tab("Settings", systemImage: "gearshape", value: AppModel.NavigationTab.settings) {
                SettingsScreen()
                    .enchronScreenAppearance()
                    .toolbarVisibility(browserTabBarVisibility, for: .tabBar)
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-settings")

            Tab(
                "Environments",
                systemImage: "mountain.2",
                value: AppModel.NavigationTab.environment
            ) {
                Color.clear
                    .toolbarVisibility(browserTabBarVisibility, for: .tabBar)
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-environment")
        }
        .toolbarVisibility(browserTabBarVisibility, for: .tabBar)
        .task {
            guard embySession.server != nil, embyHome.shelves.isEmpty else { return }
            await embyHome.refresh()
        }
#if DEBUG
        .task {
            guard EmbyLaunchRoute.current != nil else { return }
            appModel.selectedTab = .emby
        }
#endif
    }

    private var browserTabBarVisibility: Visibility {
        spatialPlatformEffectCoordinator.playerWindowIsPresent ? .hidden : .automatic
    }

    private var browserTabSelection: Binding<AppModel.NavigationTab> {
        Binding(
            get: {
                appModel.selectedTab.isContentDestination
                    ? appModel.selectedTab
                    : .files
            },
            set: selectBrowserTab
        )
    }

    private func selectBrowserTab(_ tab: AppModel.NavigationTab) {
        guard tab.isContentDestination else {
#if DEBUG
            SurfaceInputProbes.record(
                "navigation tab delivered tab=\(tab.rawValue)",
                retention: .evidence
            )
#endif
            try? playbackSession.requestEnvironmentCard(
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            return
        }
#if DEBUG
        SurfaceInputProbes.record(
            "navigation tab delivered tab=\(tab.rawValue)",
            retention: .evidence
        )
#endif
        appModel.selectedTab = tab
    }
}

extension View {
    func playbackIssueAlert(
        at location: PlaybackIssuePresentationLocation,
        onRetry: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            PlaybackIssueAlertModifier(
                location: location,
                onRetry: onRetry,
                onClose: onClose
            )
        )
    }
}

private struct PlaybackIssueAlertModifier: ViewModifier {
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    let location: PlaybackIssuePresentationLocation
    let onRetry: () -> Void
    let onClose: () -> Void

    private var presentation: (
        issue: PlaybackUserVisibleIssue,
        location: PlaybackIssuePresentationLocation
    )? {
        guard let issue = playbackRuntime.userVisibleIssue,
              issue.canPresent(at: location) else { return nil }
        return (issue, location)
    }

    func body(content: Content) -> some View {
        content.alert(
            presentation?.issue.title ?? "Playback Error",
            isPresented: Binding(
                get: { presentation != nil },
                set: { presented in
                    if presented == false,
                       let issue = presentation?.issue,
                       issue.activePlaybackFailure == nil {
                        playbackRuntime.setUserVisibleIssue(nil)
                    }
                }
            )
        ) {
            if let presentation {
                ForEach(presentation.issue.allowedActions, id: \.self) { action in
                    actionButton(action, at: presentation.location)
                }
            }
        } message: {
            if let issue = presentation?.issue {
                if issue.category == .presentationConversionFailed {
                    Text(issue.message)
                        .accessibilityIdentifier(
                            "PlayerUI-presentation-conversion-diagnostic"
                        )
                        .accessibilityValue(presentationConversionDiagnostic)
                } else if issue.category == .unsupportedVideoCodec
                    || issue.category == .mediaRequestFailed {
                    Text(issue.message)
                        .accessibilityIdentifier("Emby-Playback-Error")
                } else {
                    Text(issue.message)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        _ action: PlaybackUserVisibleIssueAction,
        at location: PlaybackIssuePresentationLocation
    ) -> some View {
        switch action {
        case .retry:
            Button("Retry") {
                recordReachability(action, at: location)
                if presentation?.issue.activePlaybackFailure == nil {
                    playbackRuntime.setUserVisibleIssue(nil)
                }
                onRetry()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(primaryActionIdentifier(at: location))
        case .close:
            Button("Close", role: .cancel) {
                recordReachability(action, at: location)
                playbackRuntime.setUserVisibleIssue(nil)
                onClose()
            }
            .accessibilityIdentifier(secondaryActionIdentifier(at: location))
        case .confirm:
            Button("OK", role: .cancel) {
                recordReachability(action, at: location)
                playbackRuntime.setUserVisibleIssue(nil)
            }
            .accessibilityIdentifier(confirmActionIdentifier(at: location))
        }
    }

    private func recordReachability(
        _ action: PlaybackUserVisibleIssueAction,
        at location: PlaybackIssuePresentationLocation
    ) {
#if DEBUG
        playbackSession.recordSurfaceInputProbe(
            "reachability playback issue delivered location=\(location) action=\(action)",
            retention: .evidence
        )
#endif
    }

    private func primaryActionIdentifier(
        at location: PlaybackIssuePresentationLocation
    ) -> String {
        switch location {
        case .mainWindow: "PlayerUI-loadFailure-primary"
        case .immersiveSpace: "PlayerUI-spatialFailure-primary"
        case .playerDeck, .mediaLibrary: "PlayerUI-playbackIssue-primary"
        }
    }

    private func secondaryActionIdentifier(
        at location: PlaybackIssuePresentationLocation
    ) -> String {
        switch location {
        case .mainWindow: "PlayerUI-loadFailure-secondary"
        case .immersiveSpace: "PlayerUI-spatialFailure-secondary"
        case .playerDeck, .mediaLibrary: "PlayerUI-playbackIssue-secondary"
        }
    }

    private func confirmActionIdentifier(
        at location: PlaybackIssuePresentationLocation
    ) -> String {
        switch location {
        case .playerDeck: "PlayerUI-unmetCapability-dismiss"
        case .mediaLibrary: "PlayerUI-presentation-conversion-dismiss"
        case .mainWindow, .immersiveSpace: "PlayerUI-playbackIssue-confirm"
        }
    }

    private var presentationConversionDiagnostic: String {
#if DEBUG
        playbackSession.lastPresentationConversionDiagnostic ?? "none"
#else
        "none"
#endif
    }
}
