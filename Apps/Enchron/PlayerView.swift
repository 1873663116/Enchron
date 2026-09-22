import DesignSystem
import Foundation
import MediaSource
import PlaybackCore
import Playback
import SwiftUI

#if DEBUG
private enum PlaybackRegressionIdentity {
    static func addressKind(_ request: PlaybackLaunchRequest?) -> String {
        guard let request else { return "none" }
        guard request.source.isRemote else { return "local-file" }
        switch request.source.url.host?.lowercased() {
        case "127.0.0.1", "::1": return "loopback"
        default: return "remote-url"
        }
    }

    static func sourceIdentity(_ request: PlaybackLaunchRequest?) -> String {
        request?.versionedIdentity.map {
            "sha256:" + $0.mediaIdentity.storageKey
        } ?? "none"
    }

    static func contentRevision(_ request: PlaybackLaunchRequest?) -> String {
        request?.versionedIdentity.map {
            "sha256:" + $0.contentRevision.storageKey
        } ?? "none"
    }

    static func collectionOrigin(_ request: PlaybackLaunchRequest?) -> String {
        request?.collectionOrigin.rawValue ?? "none"
    }
}
#endif

enum WindowPlaybackLoadingVisibility {
    static func shouldShow(
        hasPlaybackError: Bool,
        loadingVisibility: PlaybackLoadingVisibility,
        isPresentationTransitionActive: Bool
    ) -> Bool {
        hasPlaybackError == false
            && loadingVisibility == .loading
            && isPresentationTransitionActive == false
    }
}

enum PlayerWindowChromeHostingPolicy {
    static func hostsPlaybackOrnament(
        settledPresentationUsesMainWindow: Bool,
        isRevealingPlayerWindow: Bool,
        visualCutoverMayBegin: Bool
    ) -> Bool {
        settledPresentationUsesMainWindow
            || (isRevealingPlayerWindow && visualCutoverMayBegin)
    }
}

enum PlayerWindowSystemOverlayPolicy {
    static func visibility(showsPlaybackChrome: Bool) -> Visibility {
        showsPlaybackChrome ? .automatic : .hidden
    }
}

enum PlayerWindowGlassPolicy {
    static func showsGlass(
        presentationState: PlaybackRuntime.PresentationState,
        isRevealingPlayerWindow: Bool,
        hasActiveSession: Bool
    ) -> Bool {
        guard isRevealingPlayerWindow == false else { return false }
        switch presentationState {
        case .videoVisible:
            return false
        case .audioVisible:
            return true
        case .hidden, .placeholder:
            return hasActiveSession == false
        }
    }
}

public struct PlayerView: View {
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
#if DEBUG
    @Environment(SettingsViewModel.self) private var settingsViewModel
#endif

    @State private var playbackDeckOpacity: Double = 0
    @State private var reapplyVerificationSnapshotTick = 0
    private let playbackSurfaceIsEnabled: Bool

    public init(playbackSurfaceIsEnabled: Bool = true) {
        self.playbackSurfaceIsEnabled = playbackSurfaceIsEnabled
    }

    private var isRevealingPlayerWindow: Bool {
        SpatialPlatformImmersiveExitWindowRevealPolicy
            .isRevealingMainWindow(transition: playbackSession.presentationTransition)
    }

    private var showsWindowGlass: Bool {
        PlayerWindowGlassPolicy.showsGlass(
            presentationState: playbackRuntime.presentationState,
            isRevealingPlayerWindow: isRevealingPlayerWindow,
            hasActiveSession: playbackRuntime.activeSessionID != nil
        )
    }

    private var windowSurfaceIsActive: Bool {
        let transition = playbackSession.presentationTransition
        return playbackSurfaceIsEnabled
            && PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: hostedPlaybackPresentation,
                settledPresentation: playbackSession.playbackPresentation,
                previousPresentation: transition?.previousPresentation,
                targetPresentation: transition?.targetPresentation,
                sourceRendererMayRelease:
                    playbackSession.presentationSourceRendererMayRelease,
                targetRendererMayBind:
                    playbackSession.presentationTargetRendererMayBind
            )
    }

    public var body: some View {
        platformContent
#if DEBUG
            .developerStatsOverlay(
                isEnabled: settingsViewModel.preferences.developerModeEnabled
                    && playbackSession.immersiveSpaceResidency == .closed,
                sceneKey: .window
            )
#endif
            .onChange(of: playbackRuntime.residency) { _, residency in
                spatialPlatformEffectCoordinator.applyPlaybackResidency(residency)
            }
            .overlay {
#if DEBUG
                if ProcessInfo.processInfo.environment["ENCHRON_SPATIAL_ACCEPTANCE"] == "1" {
                    Text("Application playback state")
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("PlayerUI-application-state")
                        .modifier(
                            windowControlPlaneState(
                                geometryPolicy: windowPlaybackGeometryPolicy
                            )
                        )
                }
#endif
            }
    }

    private var hostsPlaybackOrnament: Bool {
        PlayerWindowChromeHostingPolicy.hostsPlaybackOrnament(
            settledPresentationUsesMainWindow: playbackSession.playbackPresentation.usesMainWindow,
            isRevealingPlayerWindow: isRevealingPlayerWindow,
            visualCutoverMayBegin: playbackSession.presentationVisualCutoverMayBegin
        )
    }

    private var showsPlaybackChrome: Bool {
        let issueRequiresPlayerDeck = playbackRuntime.userVisibleIssue?
            .canPresent(at: .playerDeck) == true
        return hostsPlaybackOrnament
            && (
                issueRequiresPlayerDeck
                    || (
                        playbackSession.showControls
                            && (playbackRuntime.presentationState == .videoVisible
                                || playbackRuntime.presentationState == .audioVisible
                                || isLeavingWindowPresentation)
                            && windowPlaybackIssue?.interruptsPlayback != true
                    )
            )
    }

    private var windowPlaybackIssue: PlaybackUserVisibleIssue? {
        guard let issue = playbackRuntime.userVisibleIssue,
              issue.canPresent(at: .mainWindow) else { return nil }
        return issue
    }

    private var platformContent: some View {
        primaryContent
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.bottom)
            ) {
                WindowPlayerDeckView(
                    presentationOverride: hostedPlaybackPresentation
                )
                .playbackIssueAlert(
                    at: .playerDeck,
                    onRetry: playbackLauncher.retryPlayback,
                    onClose: { playbackLauncher.stopPlayback(reason: .failure) }
                )
                .opacity(playbackDeckOpacity)
                .allowsHitTesting(playbackDeckOpacity > 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    playbackSession.setWindowControlsOrnamentHeight($0)
                }
            }
            .onChange(of: showsPlaybackChrome, initial: true) { _, shows in
                withAnimation(DesignTokens.AnimationToken.controlsTransition) {
                    playbackDeckOpacity = shows ? 1 : 0
                }
            }
    }

    private var primaryContent: some View {
        ZStack {
            windowPlayback

#if DEBUG
            if ProcessInfo.processInfo.environment["ENCHRON_AUTOMATION_PROBE"] == "1" {
                PlaybackAutomationStateProbe(hostedPresentation: hostedPlaybackPresentation)
            }
#endif
        }
        .enchronWindowGlassBackground(showsWindowGlass ? .always : .never)
        .persistentSystemOverlays(
            PlayerWindowSystemOverlayPolicy.visibility(
                showsPlaybackChrome: showsPlaybackChrome
            )
        )
        .onChange(of: showsWindowGlass, initial: true) { _, shows in
            playbackSession.recordSurfaceInputProbe(
                "windowGlass"
                    + " shows=\(shows)"
                    + " presentationState=\(playbackRuntime.presentationState)"
                    + " revealing=\(isRevealingPlayerWindow)"
                    + " transition=\(playbackSession.presentationTransition != nil)"
                    + " session=\(playbackRuntime.activeSessionID != nil)",
                retention: .evidence
            )
        }
    }

    @ViewBuilder
    private var windowPlayback: some View {
        let geometryPolicy = windowPlaybackGeometryPolicy
        WindowPlaybackRootView(
            geometryPolicy: geometryPolicy,
            geometryRefreshRevision: spatialPlatformEffectCoordinator
                .mainWindowPlaybackSurfaceRefreshRevision,
            showsWindowChrome: showsPlaybackChrome
                && hostedPlaybackPresentation.usesMainWindow,
            onWindowSceneChange: { windowScene in
                spatialPlatformEffectCoordinator.recordWindowScene(
                    windowScene,
                    for: .player
                )
            },
            onGeometryRefresh: { event in
                switch event {
                case let .requested(revision, size):
                    playbackSession.recordSurfaceInputProbe(
                        "mainWindowGeometryRefresh requestedRevision=\(revision)"
                            + " size=\(size.width)x\(size.height)"
                    )
                case let .failed(revision, message):
                    playbackSession.recordSurfaceInputProbe(
                        "mainWindowGeometryRefresh failedRevision=\(revision)"
                            + " error=\(message)"
                    )
                }
            },
            onTopChromeOcclusionChange: {
                playbackSession.setWindowTopChromeFraction($0)
            },
            onSurfaceHeightChange: {
                playbackSession.setWindowSurfaceHeight($0)
            }
        ) {
            windowPlaybackCanvas
        } topChrome: {
            PlayerInfoBarView(
                controlsVisible: showsPlaybackChrome,
                onSecondaryMenuVisibilityChange: {
                    playbackSession.setWindowSecondaryMenuPresented($0)
                    playbackSession.setControlsFocused($0)
#if DEBUG
                    playbackSession.recordSurfaceInputProbe(
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
        .modifier(windowControlPlaneState(geometryPolicy: geometryPolicy))
        .opacity(windowPlaybackOpacity)
        .animation(
            PlaybackPresentationTransitionAppearance.animation(
                for: windowPlaybackOpacity
            ),
            value: windowPlaybackOpacity
        )
        .allowsHitTesting(windowPlaybackOpacity > 0)
        .accessibilityHidden(windowPlaybackOpacity == 0)
        .task {
            guard reapplyVerificationIsEnabled else { return }
            while !Task.isCancelled {
                reapplyVerificationSnapshotTick &+= 1
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private var windowPlaybackCanvas: some View {
        let showsLoadingChrome = WindowPlaybackLoadingVisibility.shouldShow(
            hasPlaybackError: windowPlaybackIssue?.interruptsPlayback == true,
            loadingVisibility: playbackRuntime.loadingState.visibility,
            isPresentationTransitionActive: playbackSession.presentationTransition != nil
        )

        return ZStack {
            if playbackRuntime.mediaKind == .audioOnly {
                AudioSpectrumSurface(frame: playbackRuntime.audioSpectrumFrame)
                    .contentShape(.interaction, Rectangle())
                    .onTapGesture {
                        withAnimation(DesignTokens.AnimationToken.controlsTransition) {
                            PlaybackSurfaceInputAction.perform(
                                .windowSwiftUI,
                                appModel: playbackSession
                            )
                        }
                    }
            } else {
                PlaybackVideoSurface(
                    presentation: hostedPlaybackPresentation,
                    isActive: windowSurfaceIsActive,
                    viewportRefreshRevision: spatialPlatformEffectCoordinator
                        .mainWindowPlaybackSurfaceRefreshRevision,
                    onViewportRefreshApplied: {
                        spatialPlatformEffectCoordinator
                            .recordMainWindowPlaybackSurfaceRefreshApplied($0)
                    }
                )
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
                LoadingSpinner(
                    sourceReadBytesPerSecond: {
                        playbackRuntime.outputObservation()
                            .sourceReadBytesPerSecond
                    },
                    sourceReadPendingSeconds: {
                        playbackRuntime.outputObservation()
                            .sourceReadPendingSeconds
                    }
                )
                    .enchronSpatialFrame(depth: 0)
                    .enchronSpatialOffset(
                        z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
                    )
                    .accessibilityIdentifier("PlayerUI-loading-spinner")
                    .accessibilityLabel("Loading")
                    .allowsHitTesting(false)
            }

        }
        .playbackIssueAlert(
            at: .mainWindow,
            onRetry: playbackLauncher.retryPlayback,
            onClose: { playbackLauncher.stopPlayback(reason: .failure) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-\(hostedPlaybackPresentation.rawValue)-playback")
        .accessibilityValue(playbackRuntime.lifecycle.label)
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

    private func windowControlPlaneState(
        geometryPolicy: WindowPlaybackGeometryPolicy
    ) -> WindowControlPlaneStateModifier {
        WindowControlPlaneStateModifier(
            geometryPolicy: geometryPolicy,
            reapplyVerificationSnapshotTick: reapplyVerificationSnapshotTick,
            showsPlaybackChrome: showsPlaybackChrome,
            windowPlaybackIssue: windowPlaybackIssue,
            windowPlaybackOpacity: windowPlaybackOpacity,
            windowPlaybackAcceptsInput: windowPlaybackAcceptsInput
        )
    }

    private var hostedPlaybackPresentation: PlaybackPresentation {
        if let target = playbackSession.presentationTransition?.targetPresentation,
           target.usesMainWindow {
            return target
        }
        let settled = playbackSession.playbackPresentation
        return settled.usesMainWindow
            ? settled
            : settled.contentFamily.mainWindowPresentation
    }

    private var isLeavingWindowPresentation: Bool {
        playbackSession.presentationTransition?.previousPresentation.usesMainWindow == true
            && playbackSession.presentationTransition?.targetPresentation.usesMainWindow == false
    }

    private var windowPlaybackOpacity: Double {
        PlaybackPresentationTransitionAppearance.windowSceneHostOpacity(
            for: hostedPlaybackPresentation,
            settledPresentation: playbackSession.playbackPresentation,
            transition: playbackSession.presentationTransition,
            visualCutoverMayBegin: playbackSession.presentationVisualCutoverMayBegin
        )
    }

    private var windowPlaybackAcceptsInput: Bool {
        PlaybackPresentationTransitionAppearance.acceptsInput(
            for: hostedPlaybackPresentation,
            settledPresentation: playbackSession.playbackPresentation,
            transition: playbackSession.presentationTransition
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
}

private struct WindowControlPlaneStateModifier: ViewModifier {
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    let geometryPolicy: WindowPlaybackGeometryPolicy
    let reapplyVerificationSnapshotTick: Int
    let showsPlaybackChrome: Bool
    let windowPlaybackIssue: PlaybackUserVisibleIssue?
    let windowPlaybackOpacity: Double
    let windowPlaybackAcceptsInput: Bool

    func body(content: Content) -> some View {
#if DEBUG
        content.accessibilityValue(stateValue)
#else
        content
#endif
    }

#if DEBUG
    private var stateValue: String {
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
        let presentationRecord = debugSnapshot?.presentationState
        let displayedFrameObservations = (
            debugSnapshot?.rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let environment = PlaybackStateAccessibility.environmentAccessibilityValues(
            for: playbackSession.environmentContext
        )
        let panoramaReturnEnvironment = PlaybackStateAccessibility.environmentAccessibilityValues(
            for: playbackSession.panoramaReturnEnvironmentContext
        )
        let immersionAmount = playbackSession.lastObservedImmersionAmount.map {
            String($0)
        } ?? "none"
        let skyboxOpacity = playbackSession.environmentSkyboxOpacity.map {
            String(format: "%.4f", $0)
        } ?? "none"
        let loadingSpinnerVisible = WindowPlaybackLoadingVisibility.shouldShow(
            hasPlaybackError: windowPlaybackIssue?.interruptsPlayback == true,
            loadingVisibility: output.loadingVisibility,
            isPresentationTransitionActive: playbackSession.presentationTransition != nil
        )
        let deliveryContinuity = debugSnapshot?.deliveryContinuity
        let loadingEvidenceIncident = deliveryContinuity?.evidence
            .map { String($0.incidentID) } ?? "none"
        let loadingEvidenceFrozenMediaTime = deliveryContinuity?.evidence
            .map { String($0.frozenMediaTimeSeconds) } ?? "none"
        let loadingEvidenceRecoveredMediaTime = deliveryContinuity?.evidence?
            .recoveredMediaTimeSeconds.map { String($0) } ?? "none"
        let loadingEvidencePhase = deliveryContinuity?.phase.rawValue ?? "none"
        let loadingEvidenceSource = deliveryContinuity?.evidence?
            .detectionSource.rawValue ?? "none"
        let loadingEvidenceLanes = deliveryContinuity?.evidence?
            .requiredLanes.joined(separator: "+") ?? "none"
        let loadingEvidenceRateGeneration = deliveryContinuity?.evidence
            .map { String($0.rateApplicationGeneration) } ?? "none"
        let loadingEvidenceVideoEpoch = deliveryContinuity?.evidence
            .map { String($0.videoStreamEpoch) } ?? "none"
        let loadingEvidenceAudioEpoch = deliveryContinuity?.evidence
            .map { String($0.audioStreamEpoch) } ?? "none"
        let loadingEvidenceRequestedRate = deliveryContinuity?.evidence
            .map { String($0.requestedRate) } ?? "none"
        let loadingEvidenceExhaustedEnds = deliveryContinuity?.evidence?
            .exhaustedPresentationEndSeconds.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: "+") ?? "none"
        let loadingEvidenceRecoveredEnds = deliveryContinuity?.evidence?
            .recoveredPresentationEndSeconds?
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: "+") ?? "none"
        let loadingCausalRuntimeGeneration: String
        let loadingCausalRequestID: String
        let loadingCausalTechnicalSessionID: String
        switch output.loadingCausalEvidence {
        case .opening(let evidence):
            loadingCausalRuntimeGeneration = String(evidence.runtimeGeneration)
            loadingCausalRequestID = evidence.requestID
            loadingCausalTechnicalSessionID = evidence.technicalSessionID ?? "none"
        case .seeking(let evidence):
            loadingCausalRuntimeGeneration = String(evidence.runtimeGeneration)
            loadingCausalRequestID = "none"
            loadingCausalTechnicalSessionID = evidence.technicalSessionID
        case .recovering(let evidence):
            loadingCausalRuntimeGeneration = String(evidence.runtimeGeneration)
            loadingCausalRequestID = "none"
            loadingCausalTechnicalSessionID = evidence.technicalSessionID
        case .starved(let evidence):
            loadingCausalRuntimeGeneration = String(evidence.runtimeGeneration)
            loadingCausalRequestID = "none"
            loadingCausalTechnicalSessionID = evidence.technicalSessionID
        case nil:
            loadingCausalRuntimeGeneration = "none"
            loadingCausalRequestID = "none"
            loadingCausalTechnicalSessionID = "none"
        }
        var fields: [String] = [
            "active=\(playbackRuntime.hasActivePlaybackRequest)",
            "formatReady=\(playbackRuntime.mediaFormatIsKnown)",
            "presentation=\(playbackSession.playbackPresentation.rawValue)",
            "transition=\(playbackSession.presentationTransition?.targetPresentation.rawValue ?? "none")",
            "pendingSpatialEffect=\(playbackSession.pendingSpatialPlatformEffect == nil ? "none" : "present")",
            "sourceRendererMayRelease=\(playbackSession.presentationSourceRendererMayRelease)",
            "targetRendererMayBind=\(playbackSession.presentationTargetRendererMayBind)",
            "immersiveSpaceResidency=\(String(describing: playbackSession.immersiveSpaceResidency))",
            "immersiveSpaceLifecycleRevision=\(playbackSession.immersiveSpaceLifecycleRevision)",
            "environmentCardResidency=\(String(describing: playbackSession.environmentCardResidency))",
            "environment=\(environment.environment)",
            "environmentEffect=\(environment.effect)",
            "panoramaReturnEnvironment=\(panoramaReturnEnvironment.environment)",
            "panoramaReturnEnvironmentEffect=\(panoramaReturnEnvironment.effect)",
            "immersionAmount=\(immersionAmount)",
            "skyboxOpacity=\(skyboxOpacity)",
            "skyboxActive=\(playbackSession.environmentSkyboxIsActive)",
            "surfacePreparation=\(playbackSession.spatialPlaybackSurfacePreparationStage.replacingOccurrences(of: ";", with: ","))",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "firstTechnicalSessionAttachment=\(playbackRuntime.firstAttachedPresentationForActiveTechnicalSession?.rawValue ?? "none")",
            "rendererConsumer=\(playbackRuntime.rendererConsumerPresentation?.rawValue ?? "none")",
            "rendererConsumerEntity=\(playbackRuntime.rendererConsumerEntityID == nil ? "none" : "present")",
            "playbackEntity=\(playbackVideoEntityStore.entityID)",
            "controls=\(playbackSession.showControls ? "shown" : "hidden")",
            "lastPlatformOperation=\(spatialPlatformEffectCoordinator.lastPlatformOperation)",
            "lastExecutionCheckpoint=\(spatialPlatformEffectCoordinator.lastExecutionCheckpoint)",
            "executionAttemptCount=\(spatialPlatformEffectCoordinator.executionAttemptCount)",
            "lastExecutionResolution=\(spatialPlatformEffectCoordinator.lastExecutionResolution)",
            "portalViewportRefreshRevision=\(spatialPlatformEffectCoordinator.mainWindowPlaybackSurfaceRefreshRevision)",
            "portalViewportAppliedRefreshRevision=\(spatialPlatformEffectCoordinator.mainWindowPlaybackSurfaceAppliedRefreshRevision)",
            "conversionDiagnostic=\((playbackSession.lastPresentationConversionDiagnostic ?? "none").replacingOccurrences(of: ";", with: ","))",
            "chrome=\(showsPlaybackChrome ? "on" : "off")",
            "windowOpacityTarget=\(windowPlaybackOpacity)",
            "windowInteractive=\(windowPlaybackAcceptsInput)",
            "mediaKind=\(playbackRuntime.mediaKind.rawValue)",
            "videoVisible=\(playbackRuntime.presentationState == .videoVisible)",
            "audioVisible=\(playbackRuntime.presentationState == .audioVisible)",
            "spectrumActive=\(playbackRuntime.audioSpectrumFrame.bands.contains(where: { $0 > 0.01 }))",
            "projection=\(playbackRuntime.effectiveProjectionType.rawValue)",
            "horizontalFieldOfViewDegrees=\(playbackRuntime.effectiveHorizontalFieldOfViewDegrees)",
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
            "sampleHasLhvC=\(debugSnapshot?.lastVideoSample?.formatSignaling.lhvC.value.map(String.init) ?? "none")",
            "rendererHasLhvC=\(debugSnapshot?.lastAcceptedRendererInput?.formatSignaling?.lhvC.value.map(String.init) ?? "none")",
            "rendererInputIsMultiview=\(playbackRuntime.diagnostics.rendererInputIsMultiview.map(String.init) ?? "none")",
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
            "tapTrace=\(playbackSession.debugSurfaceTapTrace)",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "residency=\(playbackRuntime.residency.probeDescription)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "mediaName=\((playbackRuntime.currentLaunchRequest?.displayName ?? "none").replacingOccurrences(of: ";", with: ","))",
            "playbackAddressKind=\(PlaybackRegressionIdentity.addressKind(playbackRuntime.currentLaunchRequest))",
            "collectionOrigin=\(PlaybackRegressionIdentity.collectionOrigin(playbackRuntime.currentLaunchRequest))",
            "sourceIdentity=\(PlaybackRegressionIdentity.sourceIdentity(playbackRuntime.currentLaunchRequest))",
            "contentRevision=\(PlaybackRegressionIdentity.contentRevision(playbackRuntime.currentLaunchRequest))",
            "resumePromptPresentations=\(playbackLauncher.resumePromptPresentationCount)",
            "automaticResumeBypasses=\(playbackLauncher.automaticResumeBypassCount)",
            "pendingResumePrompt=\(playbackLauncher.pendingResumeDecision != nil)",
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
        fields.append(contentsOf: [
            "loadingVisibility=\(output.loadingVisibility.rawValue)",
            "loadingStage=\(output.loadingStage?.rawValue ?? "none")",
            "loadingRuntimeGeneration=\(loadingCausalRuntimeGeneration)",
            "loadingRequestID=\(loadingCausalRequestID)",
            "loadingTechnicalSessionID=\(loadingCausalTechnicalSessionID)",
            "loadingEvidencePhase=\(loadingEvidencePhase)",
            "loadingEvidenceIncident=\(loadingEvidenceIncident)",
            "loadingEvidenceSource=\(loadingEvidenceSource)",
            "loadingEvidenceLanes=\(loadingEvidenceLanes)",
            "loadingEvidenceRateGeneration=\(loadingEvidenceRateGeneration)",
            "loadingEvidenceVideoEpoch=\(loadingEvidenceVideoEpoch)",
            "loadingEvidenceAudioEpoch=\(loadingEvidenceAudioEpoch)",
            "loadingEvidenceRequestedRate=\(loadingEvidenceRequestedRate)",
            "loadingEvidenceFrozenMediaTime=\(loadingEvidenceFrozenMediaTime)",
            "loadingEvidenceExhaustedEnds=\(loadingEvidenceExhaustedEnds)",
            "loadingEvidenceRecoveredMediaTime=\(loadingEvidenceRecoveredMediaTime)",
            "loadingEvidenceRecoveredEnds=\(loadingEvidenceRecoveredEnds)"
        ])
        fields.append(
            contentsOf: geometryPolicy
                .diagnosticSnapshot
                .accessibilityFields
        )
        fields.append(contentsOf: PlaybackStateAccessibility.rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        fields.append(contentsOf: PlaybackStateAccessibility.deliveryAccessibilityFields(
            diagnostics: playbackRuntime.diagnostics,
            debugSnapshot: debugSnapshot
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
                + playbackSession.spatialPlaybackSurfaceObservation.accessibilityFields
        ).joined(separator: ";")
    }
#endif
}

#if DEBUG
private struct PlaybackAutomationStateProbe: View {
    @Environment(PlaybackSessionModel.self) private var playbackSession
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
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
        let transport = PlaybackTransportAvailability(
            lifecycle: playbackRuntime.productLifecycle,
            endedAffordance: playbackLauncher.endedAffordance
        )
        var fields = [
            "presentation=\(playbackSession.playbackPresentation.rawValue)",
            "hosted=\(hostedPresentation.rawValue)",
            "simulation=\(simulatedPresentation)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "firstTechnicalSessionAttachment=\(playbackRuntime.firstAttachedPresentationForActiveTechnicalSession?.rawValue ?? "none")",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "residency=\(playbackRuntime.residency.probeDescription)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "mediaName=\((playbackRuntime.currentLaunchRequest?.displayName ?? "none").replacingOccurrences(of: ";", with: ","))",
            "playbackAddressKind=\(PlaybackRegressionIdentity.addressKind(playbackRuntime.currentLaunchRequest))",
            "collectionOrigin=\(PlaybackRegressionIdentity.collectionOrigin(playbackRuntime.currentLaunchRequest))",
            "sourceIdentity=\(PlaybackRegressionIdentity.sourceIdentity(playbackRuntime.currentLaunchRequest))",
            "contentRevision=\(PlaybackRegressionIdentity.contentRevision(playbackRuntime.currentLaunchRequest))",
            "resumePromptPresentations=\(playbackLauncher.resumePromptPresentationCount)",
            "automaticResumeBypasses=\(playbackLauncher.automaticResumeBypassCount)",
            "pendingResumePrompt=\(playbackLauncher.pendingResumeDecision != nil)",
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
            "horizontalFieldOfViewDegrees=\(playbackRuntime.effectiveHorizontalFieldOfViewDegrees)",
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
            "controls=\(playbackSession.showControls ? "shown" : "hidden")",
            "primaryAction=\(transport.primaryAction.rawValue)",
            "primaryActionEnabled=\(transport.primaryActionEnabled)",
            "error=\(playbackRuntime.userVisibleIssue?.category.rawValue ?? "none")"
        ]
        fields.append(contentsOf: PlaybackStateAccessibility.rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        fields.append(contentsOf: PlaybackStateAccessibility.deliveryAccessibilityFields(
            diagnostics: playbackRuntime.diagnostics,
            debugSnapshot: debugSnapshot
        ))
        return fields.joined(separator: ";")
    }

    private var simulatedPresentation: String {
        return "none"
    }
}
#endif
