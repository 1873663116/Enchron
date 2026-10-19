import DesignSystem
import GameStreaming
import MediaServer
import Foundation
import MediaSource
import OSLog
import PlaybackCore
import Playback
import SwiftUI

public struct MainView: View {
    private let logger = Logger(subsystem: "app.enchron", category: "MainView")
    @Environment(AppModel.self) private var appModel
    @Environment(StreamingModel.self) private var streamingModel
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(MediaServerSources.self) private var serverSources
    @Environment(MediaServerSessionViewModel.self) private var embySession
    @Environment(MediaServerHomeViewModel.self) private var embyHome
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    @Environment(ConnectionSecurityPrompt.self) private var connectionSecurityPrompt
    @Environment(SettingsViewModel.self) private var settingsViewModel
#if DEBUG
    @Environment(DeveloperMetricsModel.self) private var developerMetrics
#endif

    @State private var environmentTabBarHidden = false
    @State private var environmentHomeTransitioning = false
    @State private var streamSurfaceBindingRevision: Int?
    @State private var expandedSize = BrowserWindowLayout.defaultSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            browserPrimaryContent
                .frame(
                    width: appModel.isEnvironmentHomeCompact || environmentHomeTransitioning ? expandedSize.width : nil,
                    height: appModel.isEnvironmentHomeCompact || environmentHomeTransitioning ? expandedSize.height : nil
                )
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    if !appModel.isEnvironmentHomeCompact && !environmentHomeTransitioning { expandedSize = size }
                }
                .modifier(
                    EnvironmentContentFade(
                        isCompact: appModel.isEnvironmentHomeCompact,
                        reduceMotion: reduceMotion
                    )
                )
                .clipShape(environmentRevealShape)
                .enchronGlassBackground(in: environmentRevealShape, displayMode: environmentPlateGlassMode)
                .allowsHitTesting(!appModel.isEnvironmentHomeCompact)
                .accessibilityHidden(appModel.isEnvironmentHomeCompact)

            if appModel.isEnvironmentHomeCompact {
                EnvironmentMiniControls { setEnvironmentHomeCompact(false) }
                    .transition(.asymmetric(
                        insertion: .opacity.animation(DesignTokens.AnimationToken.environmentControlsEntrance),
                        removal: .opacity.animation(DesignTokens.AnimationToken.environmentControlsExit)
                    ))
            }
        }
        .frame(
            width: appModel.isEnvironmentHomeCompact ? DesignTokens.EnvironmentHome.compactSize.width : nil,
            height: appModel.isEnvironmentHomeCompact ? DesignTokens.EnvironmentHome.compactSize.height : nil
        )
        .animation(reduceMotion ? nil : DesignTokens.AnimationToken.environmentPlateMorph, value: appModel.isEnvironmentHomeCompact)
        .browserWindowGeometry(isCompact: false) { windowScene in
            spatialPlatformEffectCoordinator.recordWindowScene(windowScene, for: .main)
        }
        .onChange(of: playbackSession.environmentCardDismissalRequestRevision) { _, _ in
            if appModel.selectedTab == .environment { appModel.selectedTab = .files }
            setEnvironmentHomeCompact(false)
            environmentTabBarHidden = false
        }
#if DEBUG
        .developerStatsOverlay(
            isEnabled: settingsViewModel.preferences.developerModeEnabled
                && playbackSession.immersiveSpaceResidency == .closed,
            sceneKey: .window
        )
        .onChange(
            of: settingsViewModel.preferences.developerModeEnabled,
            initial: true
        ) { _, isEnabled in
            if isEnabled {
                developerMetrics.droppedFrameCountSource = { [weak playbackRuntime] in
                    playbackRuntime?.diagnostics.rendererDroppedFrameCount
                }
                developerMetrics.enqueuedSampleCountSource = { [weak playbackRuntime] in
                    playbackRuntime?.diagnostics.enqueuedSampleCount
                }
                developerMetrics.start()
            } else {
                developerMetrics.stop()
                developerMetrics.droppedFrameCountSource = nil
                developerMetrics.enqueuedSampleCountSource = nil
            }
        }
#endif
        .onAppear {
            playbackRuntime.onPlaybackEnded = {
                playbackLauncher.handlePlaybackEnded()
                playbackSession.showControls = true
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
                Button("Connect Anyway", role: .destructive) {
                    connectionSecurityPrompt.resolve(approved: true)
                }
                .accessibilityIdentifier("FileBrowsing-CleartextExposure-proceed")
                Button("Cancel", role: .cancel) {
                    connectionSecurityPrompt.resolve(approved: false)
                }
                .accessibilityIdentifier("FileBrowsing-CleartextExposure-cancel")
            case .unverifiedCertificate, .none:
                Button("Trust", role: .destructive) {
                    connectionSecurityPrompt.resolve(approved: true)
                }
                .accessibilityIdentifier("FileBrowsing-CertificateTrust-trust")
                Button("Cancel", role: .cancel) {
                    connectionSecurityPrompt.resolve(approved: false)
                }
                .accessibilityIdentifier("FileBrowsing-CertificateTrust-cancel")
            }
        } message: {
            if let question = connectionSecurityPrompt.question {
                question.message
            }
        }
    }

    private var environmentRevealShape: CenteredRevealShape {
        if appModel.isEnvironmentHomeCompact {
            let restingSize = DesignTokens.EnvironmentHome.compactSize.height
            return CenteredRevealShape(
                size: CGSize(width: restingSize, height: restingSize),
                cornerRadius: restingSize / 2
            )
        }
        return CenteredRevealShape(size: expandedSize, cornerRadius: DesignTokens.Radius.card)
    }

    private var environmentPlateGlassMode: GlassBackgroundDisplayMode {
        appModel.isEnvironmentHomeCompact && environmentHomeTransitioning == false ? .never : .always
    }

    private func setEnvironmentHomeCompact(_ compact: Bool) {
        guard appModel.isEnvironmentHomeCompact != compact else { return }
        environmentHomeTransitioning = true
        environmentTabBarHidden = compact
        withAnimation(
            reduceMotion ? nil : DesignTokens.AnimationToken.environmentPlateMorph,
            completionCriteria: .removed
        ) {
            appModel.isEnvironmentHomeCompact = compact
        } completion: {
            environmentHomeTransitioning = false
        }
    }

    private func launchServerSelection(_ selection: MediaServerPlaybackSelection, session: MediaServerSessionViewModel) {
        playbackLauncher.requestPlayback {
            do {
                let request = try await session.playbackRequest(for: selection)
                SurfaceInputProbes.record("openRequestForwarded")
                return request
            } catch {
                logger.error(
                    "Emby playback request failed error=\(error.localizedDescription, privacy: .public)"
                )
                SurfaceInputProbes.record(
                    "emby playback request failed error=\(error)",
                    retention: .evidence
                )
                throw error
            }
        }
    }

    private var browserPrimaryContent: some View {
        ZStack {
            browser
            if playbackLauncher.isResolvingPlaybackRequest {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    LoadingSpinner()
                    Text("Connecting…")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignTokens.Spacing.xl)
                .enchronListGroupSurface(in: DesignTokens.ShapeToken.card)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("PlayerUI-requestResolution-spinner")
                .transition(.opacity)
            }
        }
        .animation(
            DesignTokens.AnimationToken.fadeIn,
            value: playbackLauncher.isResolvingPlaybackRequest
        )
        .alert("Resume Playback?",
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
        .playbackIssueAlert(at: .mediaLibrary, onRetry: playbackLauncher.retryPlayback)
    }

    private var browser: some View {
        TabView(selection: browserTabSelection) {
            Tab("Files", systemImage: "folder", value: AppModel.NavigationTab.files) {
                FilesScreenHost()
                    .enchronScreenAppearance()
                    .browserTabBarVisibility(browserVisibility)
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-files")

            if settingsViewModel.preferences.mediaLibraryTabs.emby {
                Tab(value: AppModel.NavigationTab.emby) {
                    MediaServerScreen { selectionResult in
                        guard let selection = try? selectionResult.get() else {
                            playbackRuntime.setUserVisibleIssue(.mediaRequestFailed)
                            return
                        }
                        playbackLauncher.decideResume(fromSeconds: selection.resumeCandidateSeconds) { resume in
                            launchServerSelection(
                                selection.replacingStartAction(resume ? .resume : .fromBeginning),
                                session: embySession
                            )
                        }
                    }
                    .enchronScreenAppearance()
                    .browserTabBarVisibility(browserVisibility)
                } label: {
                    Label("Emby", image: "EmbyTabIcon")
                }
                .accessibilityIdentifier("Emby-Navigation-Tab")
            }

            if settingsViewModel.preferences.mediaLibraryTabs.plex {
                Tab(value: AppModel.NavigationTab.plex) {
                    serverScreen(serverSources.plex)
                } label: {
                    Label("Plex", image: "PlexTabIcon")
                }
                .accessibilityIdentifier("Plex-Navigation-Tab")
            }

            if settingsViewModel.preferences.mediaLibraryTabs.jellyfin {
                Tab(value: AppModel.NavigationTab.jellyfin) {
                    serverScreen(serverSources.jellyfin)
                } label: {
                    Label("Jellyfin", image: "JellyfinTabIcon")
                }
                .accessibilityIdentifier("Jellyfin-Navigation-Tab")
            }

            if settingsViewModel.preferences.moonlightEnabled {
                Tab("Moonlight", systemImage: "desktopcomputer", value: AppModel.NavigationTab.streaming) {
                    StreamingHomeView()
                        .enchronScreenAppearance()
                        .browserTabBarVisibility(browserVisibility)
                }
                .accessibilityIdentifier("Navigation-Ornament-tab-streaming")
            }

            Tab("Settings", systemImage: "gearshape", value: AppModel.NavigationTab.settings) {
                SettingsScreen()
                    .enchronScreenAppearance()
                    .browserTabBarVisibility(browserVisibility)
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-settings")

            Tab("Environments",
                systemImage: "mountain.2",
                value: AppModel.NavigationTab.environment
            ) {
                EnvironmentHomeView(isCompact: Binding(
                    get: { appModel.isEnvironmentHomeCompact },
                    set: setEnvironmentHomeCompact
                ), availableWidth: expandedSize.width)
                .enchronScreenAppearance()
                .browserTabBarVisibility(browserVisibility)
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-environment")
        }
        .browserTabBarVisibility(browserVisibility)
        .onChange(of: settingsViewModel.preferences.mediaLibraryTabs, initial: true) { _, visibility in
            appModel.selectedTab = appModel.selectedTab.contentDestination(in: visibility)
        }
        .onChange(of: appModel.selectedTab, initial: true) { _, tab in
            appModel.selectedTab = tab.contentDestination(in: settingsViewModel.preferences.mediaLibraryTabs)
        }
        .task {
            guard embySession.server != nil, embyHome.shelves.isEmpty else { return }
            await embyHome.refresh()
        }
#if DEBUG
        .task {
            guard let route = MediaServerLaunchRoute.current else { return }
            appModel.selectedTab = switch route.kind {
            case .emby: .emby
            case .jellyfin: .jellyfin
            case .plex: .plex
            }
        }
        .task {
            guard ProcessInfo.processInfo.environment["ENCHRON_STREAMING_TAB"] == "1" else { return }
            appModel.selectedTab = .streaming
        }
#endif
        .onChange(of: streamingModel.session?.id, initial: true) { _, _ in
            syncExternallyDrivenSession()
        }
        .onChange(of: streamingModel.renderBinding?.version, initial: true) { _, _ in
            syncExternallyDrivenSession()
        }
        .onChange(of: playbackRuntime.boundVideoComponentRevision, initial: true) { _, revision in
            syncStreamSurfaceBinding(revision)
        }
    }

    /// Keeps the player window's session in step with the streaming session. The
    /// runtime holds the renderer, the presentation and the window while a
    /// stream runs; the stream's own model keeps decoding, pacing and input.
    private func syncExternallyDrivenSession() {
        guard let session = streamingModel.session else {
            guard playbackRuntime.externalVideoSessionID != nil else { return }
            let presentationLeftTheWindow =
                playbackSession.playbackPresentation.usesImmersiveSpace
                || playbackSession.pendingSpatialPlatformEffect != nil
            playbackRuntime.endExternalVideoSession()
            if presentationLeftTheWindow {
                playbackSession.requestStoppedPlaybackCleanup()
            }
            return
        }
        guard let binding = streamingModel.renderBinding else { return }
        do {
            try playbackRuntime.beginExternalVideoSession(
                sessionID: binding.sessionID.rawValue,
                renderer: binding.videoRenderer
            )
        } catch {
            logger.error(
                "stream session refused by the playback runtime session=\(session.id.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            streamingModel.disconnect()
        }
    }

    /// The stream's coordinator waits for a bound surface before it accepts
    /// decoded frames, and asks the host for a key frame when one binds. The
    /// player window's surface is the stream's surface, so its binding record is
    /// the signal the coordinator reads.
    private func syncStreamSurfaceBinding(_ revision: UInt64?) {
        guard streamingModel.session != nil else {
            streamSurfaceBindingRevision = nil
            return
        }
        guard let revision else {
            guard let boundRevision = streamSurfaceBindingRevision else { return }
            streamSurfaceBindingRevision = nil
            streamingModel.recordVideoSurfaceBinding(
                revision: boundRevision,
                bound: false
            )
            return
        }
        let boundRevision = Int(revision)
        streamSurfaceBindingRevision = boundRevision
        streamingModel.recordVideoSurfaceBinding(revision: boundRevision, bound: true)
    }

    private var browserVisibility: BrowserWindowVisibility {
        BrowserWindowVisibility(
            window: .main,
            playbackResidency: spatialPlatformEffectCoordinator.playbackResidency,
            isCompact: environmentTabBarHidden
        )
    }

    private func serverScreen(_ feature: MediaServerFeature) -> some View {
        MediaServerFeatureScreen(feature: feature) { result in
            guard let selection = try? result.get() else {
                playbackRuntime.setUserVisibleIssue(.mediaRequestFailed)
                return
            }
            playbackLauncher.decideResume(fromSeconds: selection.resumeCandidateSeconds) { resume in
                launchServerSelection(
                    selection.replacingStartAction(resume ? .resume : .fromBeginning),
                    session: feature.session
                )
            }
        }
        .enchronScreenAppearance()
        .browserTabBarVisibility(browserVisibility)
    }

    private var browserTabSelection: Binding<AppModel.NavigationTab> {
        Binding(
            get: {
                appModel.selectedTab.contentDestination(in: settingsViewModel.preferences.mediaLibraryTabs)
            },
            set: selectBrowserTab
        )
    }

    private func selectBrowserTab(_ tab: AppModel.NavigationTab) {
#if DEBUG
        SurfaceInputProbes.record(
            "navigation tab delivered tab=\(tab.rawValue)",
            retention: .evidence
        )
#endif
        appModel.selectedTab = tab.contentDestination(in: settingsViewModel.preferences.mediaLibraryTabs)
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

private struct EnvironmentContentFade: ViewModifier {
    let isCompact: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isCompact ? 0 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : (isCompact
                        ? DesignTokens.AnimationToken.environmentContentExit
                        : DesignTokens.AnimationToken.environmentContentEntrance),
                value: isCompact
            )
    }
}
