import DesignSystem
import Emby
import MediaSource
import OSLog
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

enum PlaybackSurfaceMountPolicy {
    static func shouldMount(showsWindowPlayback: Bool) -> Bool {
        showsWindowPlayback
    }
}

/// While playback is hosted off-window the main glass stays empty only for
/// the moments a scene operation is genuinely in flight. Once the immersive
/// space is closed and no transition is active, a presented main window
/// belongs to the wearer: the system can dismiss the space (crown press)
/// while the app has no scene left alive, and the window the wearer then
/// summons from the Home View must not be a blank pane. A pending platform
/// effect is deliberately not consulted because the closed, transition-free
/// main window must remain usable.
enum BrowserWindowSurfacePolicy {
    static func showsBrowser(
        hasActivePlaybackRequest: Bool,
        transitionIsActive: Bool,
        immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency
    ) -> Bool {
        guard hasActivePlaybackRequest else { return true }
        return transitionIsActive == false
            && immersiveSpaceResidency == .closed
    }
}

enum BrowserWindowGeometryPolicy {
    static func shouldRequestDefaultSize(
        hasActivePlaybackRequest: Bool,
        transitionIsActive: Bool,
        immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency
    ) -> Bool {
        hasActivePlaybackRequest == false
            && transitionIsActive == false
            && immersiveSpaceResidency == .closed
    }
}

enum WindowPlaybackLoadingVisibility {
    static func shouldShow(
        hasPlaybackError: Bool,
        presentationState: PlaybackRuntime.PresentationState,
        isPresentationTransitionActive: Bool
    ) -> Bool {
        hasPlaybackError == false
            && presentationState != .videoVisible
            && presentationState != .audioVisible
            && isPresentationTransitionActive == false
    }
}

public enum MainViewSceneRole {
    case browser
    case playback
}

public struct MainView: View {
    private let logger = Logger(subsystem: "app.enchron", category: "MainView")
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(EmbySessionViewModel.self) private var embySession
    @Environment(EmbyHomeViewModel.self) private var embyHome
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    @Environment(CertificateTrustPrompt.self) private var certificateTrustPrompt

    @State private var controlsTimer: Task<Void, Never>?
    @State private var reapplyVerificationSnapshotTick = 0
    @State private var isWindowSecondaryMenuPresented = false
    private let sceneRole: MainViewSceneRole
    private let playbackSurfaceIsEnabled: Bool

    public init(
        sceneRole: MainViewSceneRole = .browser,
        playbackSurfaceIsEnabled: Bool = true
    ) {
        self.sceneRole = sceneRole
        self.playbackSurfaceIsEnabled = playbackSurfaceIsEnabled
    }

    private var showsWindowPlayback: Bool {
        playbackRuntime.hasActivePlaybackRequest
            && (appModel.playbackPresentation.usesMainWindow
                || appModel.presentationTransition?.targetPresentation.usesMainWindow == true)
    }

    private var windowSurfaceIsActive: Bool {
        let transition = appModel.presentationTransition
        return playbackSurfaceIsEnabled
            && showsWindowPlayback
            && PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: hostedPlaybackPresentation,
                previousPresentation: transition?.previousPresentation,
                targetPresentation: transition?.targetPresentation,
                sourceRendererMayRelease:
                    appModel.presentationSourceRendererMayRelease,
                targetRendererMayBind:
                    appModel.presentationTargetRendererMayBind
            )
    }

    public var body: some View {
        platformContent
        .onAppear {
            guard sceneRole == .playback else { return }
            playbackRuntime.onPlaybackEnded = {
                let showControls = playbackLauncher.handlePlaybackEnded {
                    appModel.showControls = true
                    controlsTimer?.cancel()
                }
                if showControls {
                    appModel.showControls = true
                    controlsTimer?.cancel()
                }
            }
        }
        .onChange(of: playbackRuntime.hasActivePlaybackRequest) { _, hasActivePlaybackRequest in
            guard sceneRole == .playback else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                if hasActivePlaybackRequest {
                    scheduleControlsAutoHide()
                } else {
                    controlsTimer?.cancel()
                }
            }
        }
        .onChange(of: appModel.playbackWindowSessionIsActive) { _, isActive in
            reconcilePlaybackWindowPresentation(sessionIsActive: isActive)
        }
        .task {
            reconcilePlaybackWindowPresentation(
                sessionIsActive: appModel.playbackWindowSessionIsActive
            )
        }
        .onChange(of: appModel.lastControlsInteractionAt) { _, _ in
            guard sceneRole == .playback else { return }
            guard playbackRuntime.hasActivePlaybackRequest else { return }
            scheduleControlsAutoHide()
        }
        .onDisappear {
            controlsTimer?.cancel()
        }
        .overlay {
            if ProcessInfo.processInfo.environment["ENCHRON_SPATIAL_ACCEPTANCE"] == "1" {
                Text("Application playback state")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("PlayerUI-application-state")
                    .accessibilityValue(windowPlaybackStateValue)
            }
        }
        .alert(
            "无法验证服务器证书",
            isPresented: Binding(
                get: { certificateTrustPrompt.certificate != nil },
                set: { if $0 == false { certificateTrustPrompt.resolve(approved: false) } }
            )
        ) {
            Button("信任", role: .destructive) {
                certificateTrustPrompt.resolve(approved: true)
            }
            .accessibilityIdentifier("FileBrowsing-CertificateTrust-trust")
            Button("取消", role: .cancel) {
                certificateTrustPrompt.resolve(approved: false)
            }
            .accessibilityIdentifier("FileBrowsing-CertificateTrust-cancel")
        } message: {
            if let certificate = certificateTrustPrompt.certificate {
                Text(Self.certificateDescription(certificate))
            }
        }
    }

    private static func certificateDescription(_ certificate: ServerCertificateInfo) -> String {
        let validFrom = certificate.validFrom?.formatted(date: .abbreviated, time: .shortened)
            ?? "未知"
        let validUntil = certificate.validUntil?.formatted(date: .abbreviated, time: .shortened)
            ?? "未知"
        return "地址：\(certificate.address)\n证书名：\(certificate.certificateName)\n指纹：\(certificate.sha256Fingerprint)\n有效期：\(validFrom) – \(validUntil)"
    }

    /// Keep the controls ornament attached while this window hosts playback.
    /// Detaching it for chrome visibility rebuilds the RealityKit viewport and
    /// costs a black frame; browser content still carries no ornament geometry.
    private var hostsPlaybackOrnament: Bool {
        showsWindowPlayback && appModel.playbackPresentation.usesMainWindow
    }

    /// Player Controls and top chrome only after presentable video is up.
    private var showsPlaybackChrome: Bool {
        let issueRequiresPlayerDeck = playbackRuntime.userVisibleIssue?
            .canPresent(at: .playerDeck) == true
        let chrome = hostsPlaybackOrnament
            && (
                issueRequiresPlayerDeck
                    || (
                        appModel.showControls
                            && (playbackRuntime.presentationState == .videoVisible
                                || playbackRuntime.presentationState == .audioVisible
                                || isLeavingWindowPresentation)
                            && windowPlaybackIssue?.interruptsPlayback != true
                    )
            )
        // #region agent log
        // Publish gate inputs into the control-plane value so XCUI can prove
        // whether chrome stayed hidden after a successful showControls toggle.
        _ = chrome
        // #endregion
        return chrome
    }

    private var windowPlaybackIssue: PlaybackUserVisibleIssue? {
        guard let issue = playbackRuntime.userVisibleIssue,
              issue.canPresent(at: .mainWindow) else { return nil }
        return issue
    }

    @ViewBuilder
    private var platformContent: some View {
        switch sceneRole {
        case .browser:
            browserSceneContent
        case .playback:
            playbackSceneContent
        }
    }

    private var playbackSceneContent: some View {
        playbackPrimaryContent
            .ornament(
                visibility: hostsPlaybackOrnament ? .visible : .hidden,
                attachmentAnchor: .scene(.bottom)
            ) {
                ZStack {
                    Color.clear
                        .frame(
                            width: DesignTokens.ControlBar.outerWidth,
                            height: hostsPlaybackOrnament
                                ? collapsedWindowControlsOrnamentHeight
                                : .zero
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    if showsPlaybackChrome {
                        WindowPlayerDeckView(
                            presentationOverride: hostedPlaybackPresentation
                        )
                        .playbackIssueAlert(
                            at: .playerDeck,
                            onRetry: playbackLauncher.retryPlayback,
                            onClose: playbackLauncher.stopPlayback
                        )
                        .transition(.opacity)
                    }
                }
            }
    }

    private var browserSceneContent: some View {
        browserPrimaryContent
            .browserWindowGeometry()
    }

    private var collapsedWindowControlsOrnamentHeight: CGFloat {
        DesignTokens.Layout.playbackMediaInfoHeight
            + DesignTokens.Spacing.sm
            + DesignTokens.ProgressBar.hitHeight
            + DesignTokens.ControlBar.paddingV * 2
    }

    private var browserPrimaryContent: some View {
        ZStack {
            browserWindowSurface

        }
        .playbackIssueAlert(at: .mediaLibrary)
    }

    private var playbackPrimaryContent: some View {
        ZStack {
            windowPlayback

            if ProcessInfo.processInfo.environment["ENCHRON_AUTOMATION_PROBE"] == "1" {
                PlaybackAutomationStateProbe(hostedPresentation: hostedPlaybackPresentation)
            }

            if let decision = playbackLauncher.pendingResumeDecision {
                ResumeDecisionCard(
                    message: "Continue from \(PlaybackTimeFormatter.clock(decision.seconds)) or start from the beginning.",
                    onResume: {
#if DEBUG
                        appModel.recordSurfaceInputProbe(
                            "reachability resume decision delivered action=resume",
                            retention: .evidence
                        )
#endif
                        playbackLauncher.resumePendingPlayback()
                    },
                    onStartOver: {
#if DEBUG
                        appModel.recordSurfaceInputProbe(
                            "reachability resume decision delivered action=startOver",
                            retention: .evidence
                        )
#endif
                        playbackLauncher.startPendingPlaybackFromBeginning()
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var browserWindowSurface: some View {
        if BrowserWindowSurfacePolicy.showsBrowser(
            hasActivePlaybackRequest: playbackRuntime.hasActivePlaybackRequest,
            transitionIsActive: appModel.presentationTransition != nil,
            immersiveSpaceResidency: appModel.immersiveSpaceResidency
        ) {
            browser
        } else {
            Color.clear
        }
    }

    private var browser: some View {
        TabView(selection: browserTabSelection) {
            Tab("Files", systemImage: "folder", value: AppModel.NavigationTab.files) {
                FilesScreen()
                    .enchronScreenAppearance()
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-files")

            Tab("Emby", systemImage: "play.tv.fill", value: AppModel.NavigationTab.emby) {
                EmbyScreen { selectionResult in
                    appModel.beginPlaybackWindowSession()
                    do {
                        let selection = try selectionResult.get()
                        let request = try await embySession.playbackRequest(for: selection)
                        AppModel.recordProbe("openRequestForwarded")
                        playbackLauncher.requestPlayback(request)
                    } catch EmbyError.unsupportedVideoCodec(let codec) {
                        playbackRuntime.setUserVisibleIssue(
                            .unsupportedVideoCodec(
                                PlaybackUnsupportedVideoCodec(codecName: codec)
                            )
                        )
                    } catch {
                        logger.error(
                            "Emby playback request failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        playbackRuntime.setUserVisibleIssue(.mediaRequestFailed)
                    }
                }
                .enchronScreenAppearance()
            }
            .accessibilityIdentifier("Emby-Navigation-Tab")

            Tab("Settings", systemImage: "gearshape", value: AppModel.NavigationTab.settings) {
                SettingsScreen()
                    .enchronScreenAppearance()
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-settings")

            Tab(
                "Environments",
                systemImage: "mountain.2",
                value: AppModel.NavigationTab.environment
            ) {
                Color.clear
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-environment")
        }
        // Loads the Emby home page at launch rather than when its tab is first opened, so its
        // artwork is already decoded and the page does not stall on the way in.
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
            AppModel.recordProbe(
                "navigation tab delivered tab=\(tab.rawValue)",
                retention: .evidence
            )
#endif
            try? appModel.requestEnvironmentCard(
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            return
        }
#if DEBUG
        AppModel.recordProbe(
            "navigation tab delivered tab=\(tab.rawValue)",
            retention: .evidence
        )
#endif
        appModel.selectedTab = tab
    }

    @ViewBuilder
    private var windowPlayback: some View {
        WindowPlaybackRootView(
            geometryPolicy: windowPlaybackGeometryPolicy,
            geometryRefreshRevision: spatialPlatformEffectCoordinator
                .mainWindowPlaybackSurfaceRefreshRevision,
            freeformSizeOnDisappear: {
                BrowserWindowGeometryPolicy.shouldRequestDefaultSize(
                    hasActivePlaybackRequest: playbackRuntime.hasActivePlaybackRequest,
                    transitionIsActive: appModel.presentationTransition != nil,
                    immersiveSpaceResidency: appModel.immersiveSpaceResidency
                ) ? WindowPlaybackLayout.fallback.defaultSize : nil
            },
            showsWindowChrome: showsPlaybackChrome
                && hostedPlaybackPresentation.usesMainWindow,
            hidesSurfaceFromAccessibility: isWindowSecondaryMenuPresented,
            onWindowSceneChange: { windowScene in
                spatialPlatformEffectCoordinator.recordPlaybackWindowScene(
                    windowScene
                )
            },
            onGeometryRefresh: { event in
                switch event {
                case let .requested(revision, size):
                    appModel.recordSurfaceInputProbe(
                        "mainWindowGeometryRefresh requestedRevision=\(revision)"
                            + " size=\(size.width)x\(size.height)"
                    )
                case let .failed(revision, message):
                    appModel.recordSurfaceInputProbe(
                        "mainWindowGeometryRefresh failedRevision=\(revision)"
                            + " error=\(message)"
                    )
                }
            }
        ) {
            windowPlaybackCanvas
        } topChrome: {
            PlayerInfoBarView(
                controlsVisible: showsPlaybackChrome,
                onSecondaryMenuVisibilityChange: {
                    isWindowSecondaryMenuPresented = $0
                    appModel.setControlsFocused($0)
#if DEBUG
                    appModel.recordSurfaceInputProbe(
                        "reachability top secondary menu visible=\($0)"
                    )
#endif
                }
            )
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("PlayerUI-window-top-overlay")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-window-control-plane")
        .accessibilityValue(windowPlaybackStateValue)
        .opacity(windowPlaybackOpacity)
        .animation(
            PlaybackPresentationTransitionAppearance.animation(
                for: windowPlaybackOpacity
            ),
            value: windowPlaybackOpacity
        )
        .allowsHitTesting(windowPlaybackAcceptsInput)
        .task {
            guard reapplyVerificationIsEnabled else { return }
            while !Task.isCancelled {
                reapplyVerificationSnapshotTick &+= 1
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private var windowPlaybackCanvas: some View {
        // Keep the same RealityView mounted while loading. The system Window
        // owns the outer glass; this layer adds only the product spinner until
        // the surface reports presentable video (or a load failure).
        let showsLoadingChrome = WindowPlaybackLoadingVisibility.shouldShow(
            hasPlaybackError: windowPlaybackIssue?.interruptsPlayback == true,
            presentationState: playbackRuntime.presentationState,
            isPresentationTransitionActive: appModel.presentationTransition != nil
        )

        return ZStack {
            if playbackRuntime.mediaKind == .audioOnly {
                AudioSpectrumSurface(frame: playbackRuntime.audioSpectrumFrame)
                    .contentShape(.interaction, Rectangle())
                    .onTapGesture {
                        guard isWindowSecondaryMenuPresented == false else { return }
                        withAnimation(DesignTokens.AnimationToken.controlsTransition) {
                            PlaybackSurfaceInputAction.perform(
                                .windowSwiftUI,
                                appModel: appModel
                            )
                        }
                    }
            } else {
                PlaybackVideoSurface(
                    presentation: hostedPlaybackPresentation,
                    isActive: windowSurfaceIsActive,
                    surfaceTapIsEnabled: isWindowSecondaryMenuPresented == false,
                    viewportRefreshRevision: spatialPlatformEffectCoordinator
                        .mainWindowPlaybackSurfaceRefreshRevision,
                    onViewportRefreshApplied: {
                        spatialPlatformEffectCoordinator
                            .recordMainWindowPlaybackSurfaceRefreshApplied($0)
                    }
                )
            }

            if let lastFrame = appModel.portalExitLastFrame,
               SpatialPlatformImmersiveExitWindowRevealPolicy
                .shouldShowLastFrameBridge(
                    family: .panoramic,
                    targetIsSettled:
                        appModel.presentationVisualCutoverMayBegin,
                    hasCapturedFrame: true
                ) {
                Image(lastFrame, scale: 1, label: Text(""))
                    .resizable()
                    .scaledToFit()
                    .background(.black)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            #if DEBUG
            if ProcessInfo.processInfo.environment[
                "ENCHRON_REAL_VIDEO_AAC_DIAGNOSTIC"
            ] == "1" {
                Text("Playback diagnostic evidence")
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .accessibilityIdentifier("PlayerUI-debug-evidence")
                    .accessibilityValue(playbackRuntime.debugEvidenceJSON())
            }
            #endif

            if showsLoadingChrome, playbackLauncher.pendingResumeDecision == nil {
                LoadingSpinner(sourceReadBytesPerSecond: {
                    playbackRuntime.outputObservation().sourceReadBytesPerSecond
                })
                    .accessibilityIdentifier("PlayerUI-loading-spinner")
                    .accessibilityLabel("Loading")
                    .allowsHitTesting(false)
            }

        }
        .playbackIssueAlert(
            at: .mainWindow,
            onRetry: retryPlayback,
            onClose: playbackLauncher.stopPlayback
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-\(hostedPlaybackPresentation.rawValue)-playback")
        .accessibilityValue(playbackRuntime.lifecycle.label)
    }

    private var windowPlaybackStateValue: String {
        _ = reapplyVerificationSnapshotTick
        let position = playbackRuntime.playbackPosition
        let output = playbackRuntime.outputObservation()
        let debugSnapshot = playbackRuntime.debugSnapshot()
        let lastRendererInputEpoch = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.streamEpoch) } ?? "none"
        let lastRendererInputGraphRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.graphRevision) } ?? "none"
        let lastRendererInputFormatRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.formatRevision) } ?? "none"
        let providerProjectionKind = debugSnapshot?.providerOpen?.formatSignaling
            .projectionKind.value
            ?? debugSnapshot?.providerOpen.map {
                String(describing: $0.formatSignaling.projectionKind.availability)
            }
            ?? "none"
        let sampleProjectionKind = debugSnapshot?.lastVideoSample?.formatSignaling
            .projectionKind.value
            ?? debugSnapshot?.lastVideoSample.map {
                String(describing: $0.formatSignaling.projectionKind.availability)
            }
            ?? "none"
        let rendererProjectionKind = debugSnapshot?.lastAcceptedRendererInput?
            .formatSignaling?.projectionKind.value ?? "none"
        let rendererViewPackingKind = debugSnapshot?.lastAcceptedRendererInput?
            .formatSignaling?.viewPackingKind.value ?? "none"
        let providerTransferFunction = debugSnapshot?.providerOpen?.formatSignaling
            .transferFunction.value
            ?? debugSnapshot?.providerOpen.map {
                String(describing: $0.formatSignaling.transferFunction.availability)
            }
            ?? "none"
        let sampleTransferFunction = debugSnapshot?.lastVideoSample?.formatSignaling
            .transferFunction.value
            ?? debugSnapshot?.lastVideoSample.map {
                String(describing: $0.formatSignaling.transferFunction.availability)
            }
            ?? "none"
        let presentationRecord = debugSnapshot?.presentationState
        let displayedFrameObservations = (
            debugSnapshot?.rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let environment = PlaybackStateAccessibility.environmentAccessibilityValues(
            for: appModel.environmentContext
        )
        let panoramaReturnEnvironment = PlaybackStateAccessibility.environmentAccessibilityValues(
            for: appModel.panoramaReturnEnvironmentContext
        )
        let immersionAmount = appModel.lastObservedImmersionAmount.map {
            String($0)
        } ?? "none"
        let skyboxOpacity = appModel.environmentSkyboxOpacity.map {
            String(format: "%.4f", $0)
        } ?? "none"
        let loadingSpinnerVisible = WindowPlaybackLoadingVisibility.shouldShow(
            hasPlaybackError: windowPlaybackIssue?.interruptsPlayback == true,
            presentationState: playbackRuntime.presentationState,
            isPresentationTransitionActive: appModel.presentationTransition != nil
        )
        var fields: [String] = [
            "active=\(playbackRuntime.hasActivePlaybackRequest)",
            "formatReady=\(playbackRuntime.mediaFormatIsKnown)",
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "transition=\(appModel.presentationTransition?.targetPresentation.rawValue ?? "none")",
            "pendingSpatialEffect=\(appModel.pendingSpatialPlatformEffect == nil ? "none" : "present")",
            "sourceRendererMayRelease=\(appModel.presentationSourceRendererMayRelease)",
            "targetRendererMayBind=\(appModel.presentationTargetRendererMayBind)",
            "immersiveSpaceResidency=\(String(describing: appModel.immersiveSpaceResidency))",
            "immersiveSpaceLifecycleRevision=\(appModel.immersiveSpaceLifecycleRevision)",
            "environmentCardResidency=\(String(describing: appModel.environmentCardResidency))",
            "environment=\(environment.environment)",
            "environmentEffect=\(environment.effect)",
            "panoramaReturnEnvironment=\(panoramaReturnEnvironment.environment)",
            "panoramaReturnEnvironmentEffect=\(panoramaReturnEnvironment.effect)",
            "immersionAmount=\(immersionAmount)",
            "skyboxOpacity=\(skyboxOpacity)",
            "skyboxActive=\(appModel.environmentSkyboxIsActive)",
            "surfacePreparation=\(appModel.spatialPlaybackSurfacePreparationStage.replacingOccurrences(of: ";", with: ","))",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "firstTechnicalSessionAttachment=\(playbackRuntime.firstAttachedPresentationForActiveTechnicalSession?.rawValue ?? "none")",
            "rendererConsumer=\(playbackRuntime.rendererConsumerPresentation?.rawValue ?? "none")",
            "rendererConsumerEntity=\(playbackRuntime.rendererConsumerEntityID == nil ? "none" : "present")",
            "playbackEntity=\(playbackVideoEntityStore.entityID)",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "lastPlatformOperation=\(spatialPlatformEffectCoordinator.lastPlatformOperation)",
            "lastExecutionCheckpoint=\(spatialPlatformEffectCoordinator.lastExecutionCheckpoint)",
            "executionAttemptCount=\(spatialPlatformEffectCoordinator.executionAttemptCount)",
            "lastExecutionResolution=\(spatialPlatformEffectCoordinator.lastExecutionResolution)",
            "portalViewportRefreshRevision=\(spatialPlatformEffectCoordinator.mainWindowPlaybackSurfaceRefreshRevision)",
            "portalViewportAppliedRefreshRevision=\(spatialPlatformEffectCoordinator.mainWindowPlaybackSurfaceAppliedRefreshRevision)",
            "conversionDiagnostic=\((appModel.lastPresentationConversionDiagnostic ?? "none").replacingOccurrences(of: ";", with: ","))",
            "chrome=\(showsPlaybackChrome ? "on" : "off")",
            "windowOpacityTarget=\(windowPlaybackOpacity)",
            "windowInteractive=\(windowPlaybackAcceptsInput)",
            "mediaKind=\(playbackRuntime.mediaKind.rawValue)",
            "videoVisible=\(playbackRuntime.presentationState == .videoVisible)",
            "audioVisible=\(playbackRuntime.presentationState == .audioVisible)",
            "spectrumActive=\(playbackRuntime.audioSpectrumFrame.bands.contains(where: { $0 > 0.01 }))",
            "projection=\(playbackRuntime.effectiveProjectionType.rawValue)",
            "formatProvenance=\(playbackRuntime.activeMediaFormatProvenance.rawValue)",
            "sourceContentKind=\(playbackRuntime.sourceVideoContentKind.rawValue)",
            "effectiveContentIsPanoramic=\(playbackRuntime.effectiveContentIsPanoramic)",
            "providerProjectionKind=\(providerProjectionKind)",
            "sampleProjectionKind=\(sampleProjectionKind)",
            "rendererProjectionKind=\(rendererProjectionKind)",
            "rendererViewPackingKind=\(rendererViewPackingKind)",
            "providerCodecName=\(debugSnapshot?.providerOpen?.codecName ?? "none")",
            "providerCodecTag=\(debugSnapshot?.providerOpen?.codecTag ?? "none")",
            "providerCodecConfiguration=\(debugSnapshot?.providerOpen?.codecConfigurationSummary.value ?? "none")",
            "sampleMediaSubtype=\(debugSnapshot?.lastVideoSample?.mediaSubtype ?? "none")",
            "providerTransferFunction=\(providerTransferFunction)",
            "sampleTransferFunction=\(sampleTransferFunction)",
            "sampleHasDvcC=\(debugSnapshot?.lastVideoSample?.formatSignaling.dvcC.value.map(String.init) ?? "none")",
            "sampleHasDvvC=\(debugSnapshot?.lastVideoSample?.formatSignaling.dvvC.value.map(String.init) ?? "none")",
            "windowComponentContentType=\(playbackVideoEntityStore.realityKitContentType)",
            "corePresentationMode=\(presentationRecord?.requestedMode ?? "none")",
            "corePresentationSession=\(presentationRecord?.mediaSessionID ?? "none")",
            "corePresentationPhase=\(presentationRecord?.phase ?? "none")",
            "corePresentationComponentStatus=\(presentationRecord?.componentRenderingStatus?.value ?? "none")",
            "corePresentationDisplayedPixel=\(presentationRecord?.displayedPixelBuffer.map(String.init) ?? "none")",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "mvHEVC=\(playbackRuntime.diagnostics.isMVHEVC)",
            "windowStyle=plain",
            "loadingSpinner=\(loadingSpinnerVisible ? "on" : "off")",
            "tapTrace=\(appModel.debugSurfaceTapTrace)",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")",
            "technicalSessionReplacementStage=\(playbackRuntime.technicalSessionReplacementStage.rawValue)",
            "seekInProgress=\(playbackRuntime.seekIsInProgress)",
            "liveTechnicalSessions=\(playbackRuntime.liveTechnicalSessionCount)",
            "retiringTechnicalSessions=\(playbackRuntime.retiringTechnicalSessionCount)",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "streamEpoch=\(output.streamEpoch)",
            "videoSamples=\(output.videoSampleCount)",
            "rendererInputs=\(output.acceptedRendererInputCount)",
            "lastRendererInputEpoch=\(lastRendererInputEpoch)",
            "lastRendererInputGraphRevision=\(lastRendererInputGraphRevision)",
            "lastRendererInputFormatRevision=\(lastRendererInputFormatRevision)",
            "displayedFrameObservations=\(displayedFrameObservations)",
            "videoRendererStatus=\(playbackRuntime.diagnostics.rendererStatus)",
            "videoRendererError=\(playbackRuntime.diagnostics.rendererError)",
            "bootstrapComplete=\(output.decoderBootstrapComplete)",
            "targetRate=\(output.requestedPlaybackRate)",
            "actualRate=\(output.actualTimebaseRate)",
            "componentReady=\(output.videoComponentReady)",
            "displayedPixel=\(output.displayedPixelBuffer)",
            "videoComponentRevision=\(playbackRuntime.videoComponentRevision)",
            "boundVideoComponentRevision=\(playbackRuntime.boundVideoComponentRevision.map(String.init) ?? "none")",
            "rendererPixelVideoComponentRevision=\(playbackRuntime.rendererPixelVideoComponentRevision.map(String.init) ?? "none")",
            "rendererPixelStreamEpoch=\(playbackRuntime.rendererPixelStreamEpoch.map(String.init) ?? "none")",
            "desiredImmersiveMode=\(output.desiredImmersiveViewingMode ?? "none")",
            "actualImmersiveMode=\(output.actualImmersiveViewingMode ?? "none")",
            "desiredViewingMode=\(output.desiredViewingMode ?? "none")",
            "actualViewingMode=\(output.actualViewingMode ?? "none")",
            "desiredSpatialVideoMode=\(output.desiredSpatialVideoMode ?? "none")",
            "actualSpatialVideoMode=\(output.actualSpatialVideoMode ?? "none")",
            "hasAudio=\(output.hasAudio)",
            "audioSamples=\(output.audioSampleBufferCount)",
            "audioRendererSamples=\(output.audioRendererSampleBufferCount)",
            "audioRendererEpoch=\(output.audioRendererStreamEpoch)",
            "audioRendererStatus=\(output.audioRendererStatus)",
            "audioRendererVolume=\(output.audioRendererVolume)",
            "audioRendererMuted=\(output.audioRendererMuted)",
            "audioRendererError=\(output.audioRendererError ?? "none")",
            "audioSessionCategory=\(output.audioSessionCategory)",
            "audioSessionMode=\(output.audioSessionMode)",
            "audioOutputPorts=\(output.audioSessionOutputPortTypes.joined(separator: ","))",
            "systemOutputVolume=\(output.systemOutputVolume)",
            "audioSessionActive=\(output.audioSessionActive)",
            "audioTracks=\(playbackRuntime.availableAudioTracks.count)",
            "audioTrack=\(playbackRuntime.currentAudioTrackID ?? "none")",
            "subtitleTracks=\(playbackRuntime.availableSubtitleTracks.count)",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)",
            "error=\(playbackRuntime.userVisibleIssue?.category.rawValue ?? "none")"
        ]
        fields.append(contentsOf: PlaybackStateAccessibility.rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        #if DEBUG
        if ProcessInfo.processInfo.environment[
            "ENCHRON_VERIFY_SUFFICIENT_RATE_REAPPLY"
        ] == "1", let snapshot = playbackRuntime.debugSnapshot() {
            fields.append(
                "effectiveRate=\(snapshot.rendererState?.effectiveTimebaseRate ?? 0)"
            )
            if let reapply = snapshot.activationReapplyVerification {
                fields.append(contentsOf: [
                    "reapplyActivationSequence=\(reapply.activationSequence)",
                    "reapplyAnchorValue=\(reapply.anchorValue)",
                    "reapplyAnchorTimescale=\(reapply.anchorTimescale)",
                    "reapplyAnchorEpoch=\(reapply.anchorEpoch)",
                    "reapplyAnchorFlags=\(reapply.anchorFlags)",
                    "reapplyRequestedRate=\(reapply.requestedRate)",
                    "reapplyAudioRequired=\(reapply.audioRequired)",
                    "reapplyVideoSufficient=\(reapply.videoHasSufficientMedia)",
                    "reapplyAudioSufficient=\(reapply.audioHasSufficientMedia)",
                    "reapplyDirectRate=\(reapply.directRate)",
                    "reapplyEffectiveRate=\(reapply.effectiveRate)",
                    "reapplyAttemptCount=\(reapply.attemptCount)",
                    "reapplyClaimCount=\(reapply.attemptCount)",
                    "reapplyOutcome=\(reapply.outcome.rawValue)"
                ])
            }
        }
        #endif
        return (
            fields
                + appModel.spatialPlaybackSurfaceObservation.accessibilityFields
        ).joined(separator: ";")
    }

    private var reapplyVerificationIsEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment[
            "ENCHRON_VERIFY_SUFFICIENT_RATE_REAPPLY"
        ] == "1"
        #else
        false
        #endif
    }

    private var hostedPlaybackPresentation: PlaybackPresentation {
        if let target = appModel.presentationTransition?.targetPresentation,
           target.usesMainWindow {
            return target
        }
        return appModel.playbackPresentation.usesMainWindow
            ? appModel.playbackPresentation
            : .window
    }

    private var isLeavingWindowPresentation: Bool {
        appModel.presentationTransition?.previousPresentation.usesMainWindow == true
            && appModel.presentationTransition?.targetPresentation.usesMainWindow == false
    }

    private var windowPlaybackOpacity: Double {
        PlaybackPresentationTransitionAppearance.windowSceneHostOpacity(
            for: hostedPlaybackPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition,
            visualCutoverMayBegin: appModel.presentationVisualCutoverMayBegin
        )
    }

    private var windowPlaybackAcceptsInput: Bool {
        PlaybackPresentationTransitionAppearance.acceptsInput(
            for: hostedPlaybackPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    private var windowPlaybackLayout: WindowPlaybackLayout {
        WindowPlaybackLayout(
            resolution: playbackRuntime.displayMediaProfile?.resolution,
            pixelAspectRatio: playbackRuntime.displayMediaProfile?.pixelAspectRatio ?? .square,
            stereoLayout: playbackRuntime.effectiveStereoLayout
        )
    }

    private var windowPlaybackGeometryPolicy: WindowPlaybackGeometryPolicy {
        if playbackRuntime.mediaKind == .audioOnly {
            return .audioOnly
        }
        return WindowPlaybackGeometryPolicy(
            presentation: hostedPlaybackPresentation,
            videoLayout: windowPlaybackLayout
        )
    }

    private func retryPlayback() {
        playbackRuntime.setUserVisibleIssue(nil)
        playbackLauncher.retryPlayback()
    }

    private func scheduleControlsAutoHide() {
        controlsTimer?.cancel()
        guard appModel.controlsAutoHideSeconds > 0 else { return }
        let delay = Duration.seconds(appModel.controlsAutoHideSeconds)
        controlsTimer = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  appModel.canAutoHideControls,
                  playbackRuntime.lifecycle == .playing else { return }
            withAnimation(DesignTokens.AnimationToken.controlsTransition) {
                appModel.showControls = false
            }
        }
    }

    private func reconcilePlaybackWindowPresentation(
        sessionIsActive: Bool
    ) {
        spatialPlatformEffectCoordinator.reconcilePlaybackWindowPresentation(
            hostWindow: sceneRole == .browser ? .main : .playback,
            sessionIsActive: sessionIsActive
        )
    }

}

private struct PlaybackAutomationStateProbe: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    let hostedPresentation: PlaybackPresentation

    var body: some View {
        Text(stateValue)
            .font(.system(size: 1))
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityIdentifier("PlayerUI-playback-state")
            .accessibilityLabel(stateValue)
    }

    private var stateValue: String {
        let position = playbackRuntime.playbackPosition
        let output = playbackRuntime.outputObservation()
        let debugSnapshot = playbackRuntime.debugSnapshot()
        let lastRendererInputEpoch = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.streamEpoch) } ?? "none"
        let lastRendererInputGraphRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.graphRevision) } ?? "none"
        let lastRendererInputFormatRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.formatRevision) } ?? "none"
        let providerProjectionKind = debugSnapshot?.providerOpen?.formatSignaling
            .projectionKind.value
            ?? debugSnapshot?.providerOpen.map {
                String(describing: $0.formatSignaling.projectionKind.availability)
            }
            ?? "none"
        let sampleProjectionKind = debugSnapshot?.lastVideoSample?.formatSignaling
            .projectionKind.value
            ?? debugSnapshot?.lastVideoSample.map {
                String(describing: $0.formatSignaling.projectionKind.availability)
            }
            ?? "none"
        let rendererProjectionKind = debugSnapshot?.lastAcceptedRendererInput?
            .formatSignaling?.projectionKind.value ?? "none"
        let rendererViewPackingKind = debugSnapshot?.lastAcceptedRendererInput?
            .formatSignaling?.viewPackingKind.value ?? "none"
        let presentationRecord = debugSnapshot?.presentationState
        let displayedFrameObservations = (
            debugSnapshot?.rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let outputBoundary = PlaybackOutputVerification.firstIncompleteBoundary(
            current: output
        )
        let demuxBuffer = playbackRuntime.diagnostics.demuxBuffer
        var fields = [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "hosted=\(hostedPresentation.rawValue)",
            "simulation=\(simulatedPresentation)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "firstTechnicalSessionAttachment=\(playbackRuntime.firstAttachedPresentationForActiveTechnicalSession?.rawValue ?? "none")",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")",
            "technicalSessionReplacementStage=\(playbackRuntime.technicalSessionReplacementStage.rawValue)",
            "seekInProgress=\(playbackRuntime.seekIsInProgress)",
            "liveTechnicalSessions=\(playbackRuntime.liveTechnicalSessionCount)",
            "retiringTechnicalSessions=\(playbackRuntime.retiringTechnicalSessionCount)",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "streamEpoch=\(output.streamEpoch)",
            "videoSamples=\(output.videoSampleCount)",
            "rendererInputs=\(output.acceptedRendererInputCount)",
            "lastRendererInputEpoch=\(lastRendererInputEpoch)",
            "lastRendererInputGraphRevision=\(lastRendererInputGraphRevision)",
            "lastRendererInputFormatRevision=\(lastRendererInputFormatRevision)",
            "providerProjectionKind=\(providerProjectionKind)",
            "sampleProjectionKind=\(sampleProjectionKind)",
            "rendererProjectionKind=\(rendererProjectionKind)",
            "rendererViewPackingKind=\(rendererViewPackingKind)",
            "windowComponentContentType=\(playbackVideoEntityStore.realityKitContentType)",
            "corePresentationMode=\(presentationRecord?.requestedMode ?? "none")",
            "corePresentationPhase=\(presentationRecord?.phase ?? "none")",
            "corePresentationComponentStatus=\(presentationRecord?.componentRenderingStatus?.value ?? "none")",
            "corePresentationDisplayedPixel=\(presentationRecord?.displayedPixelBuffer.map(String.init) ?? "none")",
            "displayedFrameObservations=\(displayedFrameObservations)",
            "videoRendererStatus=\(playbackRuntime.diagnostics.rendererStatus)",
            "videoRendererError=\(playbackRuntime.diagnostics.rendererError)",
            "bootstrapComplete=\(output.decoderBootstrapComplete)",
            "targetRate=\(output.requestedPlaybackRate)",
            "actualRate=\(output.actualTimebaseRate)",
            "componentReady=\(output.videoComponentReady)",
            "displayedPixel=\(output.displayedPixelBuffer)",
            "videoComponentRevision=\(playbackRuntime.videoComponentRevision)",
            "boundVideoComponentRevision=\(playbackRuntime.boundVideoComponentRevision.map(String.init) ?? "none")",
            "rendererPixelVideoComponentRevision=\(playbackRuntime.rendererPixelVideoComponentRevision.map(String.init) ?? "none")",
            "rendererPixelStreamEpoch=\(playbackRuntime.rendererPixelStreamEpoch.map(String.init) ?? "none")",
            "hasAudio=\(output.hasAudio)",
            "audioSamples=\(output.audioSampleBufferCount)",
            "audioRendererSamples=\(output.audioRendererSampleBufferCount)",
            "audioRendererEpoch=\(output.audioRendererStreamEpoch)",
            "audioRendererStatus=\(output.audioRendererStatus)",
            "audioRendererVolume=\(output.audioRendererVolume)",
            "audioRendererMuted=\(output.audioRendererMuted)",
            "audioRendererError=\(output.audioRendererError ?? "none")",
            "audioSessionCategory=\(output.audioSessionCategory)",
            "audioSessionMode=\(output.audioSessionMode)",
            "audioOutputPorts=\(output.audioSessionOutputPortTypes.joined(separator: ","))",
            "systemOutputVolume=\(output.systemOutputVolume)",
            "audioSessionActive=\(output.audioSessionActive)",
            "outputBoundary=\(outputBoundary.rawValue)",
            "sourceReadBytesPerSecond=\(output.sourceReadBytesPerSecond)",
            "demuxBufferMode=\(demuxBuffer?.mode.rawValue ?? "notObserved")",
            "demuxBufferedSeconds=\(demuxBuffer.map { String($0.bufferedDurationSeconds) } ?? "notObserved")",
            "demuxTargetSeconds=\(demuxBuffer.map { String($0.targetDurationSeconds) } ?? "notObserved")",
            "demuxForwardBytes=\(demuxBuffer.map { String($0.forwardBufferedBytes) } ?? "notObserved")",
            "demuxForwardLimitBytes=\(demuxBuffer.map { String($0.forwardLimitBytes) } ?? "notObserved")",
            "demuxBackwardBytes=\(demuxBuffer.map { String($0.backwardBufferedBytes) } ?? "notObserved")",
            "demuxBackwardLimitBytes=\(demuxBuffer.map { String($0.backwardLimitBytes) } ?? "notObserved")",
            "demuxReconnects=\(demuxBuffer.map { String($0.reconnectAttemptCount) } ?? "notObserved")",
            "demuxReadFrames=\(demuxBuffer.map { String($0.readFrameCount) } ?? "notObserved")",
            "audioTrack=\(playbackRuntime.currentAudioTrackID ?? "none")",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)",
            "subtitleFrame=\(playbackRuntime.activeSubtitleFrame?.kind.rawValue ?? "none")",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "error=\(playbackRuntime.userVisibleIssue?.category.rawValue ?? "none")"
        ]
        fields.append(contentsOf: PlaybackStateAccessibility.rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        return fields.joined(separator: ";")
    }

    private var simulatedPresentation: String {
        return "none"
    }
}



enum PlaybackIssuePresentationScope {
    case location(PlaybackIssuePresentationLocation)
    case immersiveResident

    func resolve(
        _ issue: PlaybackUserVisibleIssue
    ) -> PlaybackIssuePresentationLocation? {
        switch self {
        case .location(let location):
            return issue.canPresent(at: location) ? location : nil
        case .immersiveResident:
            if issue.canPresent(at: .immersiveSpace) {
                return .immersiveSpace
            }
            if issue.canPresent(at: .playerDeck) {
                return .playerDeck
            }
            return nil
        }
    }
}

extension View {
    func playbackIssueAlert(
        at location: PlaybackIssuePresentationLocation,
        onRetry: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) -> some View {
        playbackIssueAlert(
            in: .location(location),
            onRetry: onRetry,
            onClose: onClose
        )
    }

    func playbackIssueAlert(
        in scope: PlaybackIssuePresentationScope,
        onRetry: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            PlaybackIssueAlertModifier(
                scope: scope,
                onRetry: onRetry,
                onClose: onClose
            )
        )
    }
}

private struct PlaybackIssueAlertModifier: ViewModifier {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    let scope: PlaybackIssuePresentationScope
    let onRetry: () -> Void
    let onClose: () -> Void

    private var presentation: (
        issue: PlaybackUserVisibleIssue,
        location: PlaybackIssuePresentationLocation
    )? {
        guard let issue = playbackRuntime.userVisibleIssue,
              let location = scope.resolve(issue) else { return nil }
        return (issue, location)
    }

    func body(content: Content) -> some View {
        content.alert(
            presentation?.issue.title ?? "Playback Error",
            isPresented: Binding(
                get: { presentation != nil },
                set: { presented in
                    if presented == false, presentation != nil {
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
                playbackRuntime.setUserVisibleIssue(nil)
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
        appModel.recordSurfaceInputProbe(
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
        appModel.lastPresentationConversionDiagnostic ?? "none"
#else
        "none"
#endif
    }
}
