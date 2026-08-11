import DesignSystem
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI
import UIKit

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

enum PlaybackPresentationRendererBindingPolicy {
    static func shouldBindRenderer(
        for presentation: PlaybackPresentation,
        previousPresentation: PlaybackPresentation?,
        targetPresentation: PlaybackPresentation?,
        sourceRendererMayRelease: Bool,
        targetRendererMayBind: Bool
    ) -> Bool {
        guard let previousPresentation,
              let targetPresentation,
              previousPresentation != targetPresentation else {
            return true
        }

        let crossesRealityViewRoots =
            previousPresentation.usesMainWindow
            != targetPresentation.usesMainWindow
        guard crossesRealityViewRoots else {
            return true
        }
        if presentation.usesMainWindow == previousPresentation.usesMainWindow {
            return sourceRendererMayRelease == false
        }
        if presentation.usesMainWindow == targetPresentation.usesMainWindow {
            return targetRendererMayBind
        }
        return false
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
            && isPresentationTransitionActive == false
    }
}

enum PlaybackPresentationTransitionAppearance {
    static let sourceFadeDuration: TimeInterval = 2
    static let rendererTransferDelay: TimeInterval = 0.5
    static let targetFadeDuration: TimeInterval = 0.8
    static let targetPreparationOpacity = 0.001

    static func opacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool = true
    ) -> Double {
        if let transition {
            if visualCutoverMayBegin == false {
                return hostedPresentation == transition.targetPresentation
                    ? targetPreparationOpacity
                    : 1
            }
            return hostedPresentation == transition.targetPresentation
                ? 1
                : 0
        }
        return hostedPresentation == settledPresentation ? 1 : 0
    }

    /// A target Window scene must remain compositor-visible while its
    /// projected VideoPlayerComponent settles. The VideoEntity carries the
    /// preparation opacity; fading the whole SwiftUI host can keep RealityKit
    /// in Loading and deadlock the presentation conversion.
    static func windowSceneHostOpacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool = true
    ) -> Double {
        if transition != nil {
            return 1
        }
        return opacity(
            for: hostedPresentation,
            settledPresentation: settledPresentation,
            transition: transition,
            visualCutoverMayBegin: visualCutoverMayBegin
        )
    }

    /// The outgoing Window's Video Entity must not fade independently from its
    /// system Window. Otherwise the compositor can expose an empty glass
    /// surface before the Window dismissal finishes.
    static func windowVideoEntityOpacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool
    ) -> Double {
        if let transition,
           hostedPresentation == transition.previousPresentation,
           transition.previousPresentation.usesMainWindow,
           transition.targetPresentation.usesImmersiveSpace {
            return 1
        }
        return opacity(
            for: hostedPresentation,
            settledPresentation: settledPresentation,
            transition: transition,
            visualCutoverMayBegin: visualCutoverMayBegin
        )
    }

    /// A departing Player Controls Window fades through Scene dismissal so its
    /// system window and content leave as one surface with the outgoing video.
    /// Making only the SwiftUI root transparent would instead leave an empty
    /// gray visionOS window behind. A freshly opened target controls Scene may
    /// also appear just before commit, after the target surface has settled.
    static func playerControlsSceneHostOpacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?
    ) -> Double {
        if transition != nil {
            return 1
        }
        return windowSceneHostOpacity(
            for: hostedPresentation,
            settledPresentation: settledPresentation,
            transition: transition
        )
    }

    static func acceptsInput(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?
    ) -> Bool {
        transition == nil && hostedPresentation == settledPresentation
    }

    static func animation(for targetOpacity: Double) -> Animation {
        .easeInOut(
            duration: targetOpacity == 0
                ? sourceFadeDuration
                : targetFadeDuration
        )
    }
}

public struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator

    @State private var controlsTimer: Task<Void, Never>?
    @State private var reapplyVerificationSnapshotTick = 0
    @State private var isWindowSecondaryMenuPresented = false
    private let playbackSurfaceIsEnabled: Bool

    public init(playbackSurfaceIsEnabled: Bool = true) {
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
            Task { @MainActor in
                await Task.yield()
                appModel.presentDeferredPresentationConversionFailure()
            }
        }
        .onChange(of: playbackRuntime.hasActivePlaybackRequest) { _, hasActivePlaybackRequest in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                if hasActivePlaybackRequest {
                    scheduleControlsAutoHide()
                } else {
                    controlsTimer?.cancel()
                    appModel.presentDeferredPresentationConversionFailure()
                }
            }
        }
        .onChange(of: appModel.lastControlsInteractionAt) { _, _ in
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
    }

    /// Player Controls and top chrome only after presentable video is up.
    private var showsPlaybackChrome: Bool {
        let chrome =
            showsWindowPlayback
            && appModel.playbackPresentation.usesMainWindow
            && appModel.showControls
            && (playbackRuntime.presentationState == .videoVisible
                || isLeavingWindowPresentation)
            && playbackRuntime.lastErrorMessage == nil
        // #region agent log
        // Publish gate inputs into the control-plane value so XCUI can prove
        // whether chrome stayed hidden after a successful showControls toggle.
        _ = chrome
        // #endregion
        return chrome
    }

    @ViewBuilder
    private var platformContent: some View {
        primaryContent
            .ornament(
                visibility: showsPlaybackChrome ? .visible : .hidden,
                attachmentAnchor: .scene(.bottom)
            ) {
                WindowPlayerDeckView(
                    presentationOverride: hostedPlaybackPresentation
                )
            }
    }

    private var primaryContent: some View {
        ZStack {
            if PlaybackSurfaceMountPolicy.shouldMount(
                showsWindowPlayback: showsWindowPlayback
            ) {
                windowPlayback
            } else {
                browserWindowSurface
            }

            if ProcessInfo.processInfo.environment["ENCHRON_AUTOMATION_PROBE"] == "1" {
                PlaybackAutomationStateProbe(hostedPresentation: hostedPlaybackPresentation)
            }

            if let decision = playbackLauncher.pendingResumeDecision {
                ResumeDecisionCard(
                    message: "Continue from \(PlaybackTimeFormatter.clock(decision.seconds)) or start from the beginning.",
                    onResume: playbackLauncher.resumePendingPlayback,
                    onStartOver: playbackLauncher.startPendingPlaybackFromBeginning
                )
            }
        }
        .alert(
            "转换失败",
            isPresented: Binding(
                get: { appModel.presentationConversionFailureMessage != nil },
                set: {
                    if $0 == false {
                        appModel.presentationConversionFailureMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                appModel.presentationConversionFailureMessage = nil
            }
        } message: {
            Text(
                appModel.presentationConversionFailureMessage
                    ?? "无法切换播放显示方式，已返回媒体资料库。"
            )
            .accessibilityIdentifier("PlayerUI-presentation-conversion-diagnostic")
            .accessibilityValue(presentationConversionDiagnosticAccessibilityValue)
        }
    }

    private var presentationConversionDiagnosticAccessibilityValue: String {
#if DEBUG
        appModel.lastPresentationConversionDiagnostic ?? "none"
#else
        "none"
#endif
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
            }
            .accessibilityIdentifier("Navigation-Ornament-tab-files")

            Tab("Settings", systemImage: "gearshape", value: AppModel.NavigationTab.settings) {
                SettingsScreen()
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
            try? appModel.requestEnvironmentCard(
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
            return
        }
        appModel.selectedTab = tab
    }

    @ViewBuilder
    private var windowPlayback: some View {
        WindowPlaybackRootView(
            geometryPolicy: windowPlaybackGeometryPolicy,
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
            onSurfaceTap: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    PlaybackSurfaceInputAction.perform(
                        .windowSwiftUI,
                        appModel: appModel
                    )
                }
            },
            onWindowSceneChange: { windowScene in
                spatialPlatformEffectCoordinator.recordMainWindowScene(
                    windowScene
                )
            }
        ) {
            windowPlaybackCanvas
        } topChrome: {
            PlayerInfoBarView(
                onSecondaryMenuVisibilityChange: {
                    isWindowSecondaryMenuPresented = $0
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
            hasPlaybackError: playbackRuntime.lastErrorMessage != nil,
            presentationState: playbackRuntime.presentationState,
            isPresentationTransitionActive: appModel.presentationTransition != nil
        )

        return ZStack {
            PlaybackVideoSurface(
                presentation: hostedPlaybackPresentation,
                isActive: windowSurfaceIsActive
            )

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

            if showsLoadingChrome {
                LoadingSpinner()
                    .accessibilityIdentifier("PlayerUI-loading-spinner")
                    .accessibilityLabel("Loading")
                    .allowsHitTesting(false)
            }

        }
        .alert(
            "Failed to Load",
            isPresented: Binding(
                get: { playbackRuntime.lastErrorMessage != nil },
                set: { if !$0 { playbackRuntime.lastErrorMessage = nil } }
            )
        ) {
            Button("Retry", action: retryPlayback)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("PlayerUI-loadFailure-primary")
            Button("Close", role: .cancel, action: playbackLauncher.stopPlayback)
                .accessibilityIdentifier("PlayerUI-loadFailure-secondary")
        } message: {
            Text(playbackRuntime.lastErrorMessage ?? "Playback could not be started.")
        }
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
        let environment = environmentAccessibilityValues(
            for: appModel.environmentContext
        )
        let panoramaReturnEnvironment = environmentAccessibilityValues(
            for: appModel.panoramaReturnEnvironmentContext
        )
        let immersionAmount = appModel.lastObservedImmersionAmount.map {
            String($0)
        } ?? "none"
        let skyboxOpacity = appModel.environmentSkyboxOpacity.map {
            String(format: "%.4f", $0)
        } ?? "none"
        let loadingSpinnerVisible = WindowPlaybackLoadingVisibility.shouldShow(
            hasPlaybackError: playbackRuntime.lastErrorMessage != nil,
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
            "conversionDiagnostic=\((appModel.lastPresentationConversionDiagnostic ?? "none").replacingOccurrences(of: ";", with: ","))",
            "playerControlsWindowResidency=\(spatialPlatformEffectCoordinator.playerControlsWindowObservedResidency)",
            "playerControlsWindowObservationRevision=\(spatialPlatformEffectCoordinator.playerControlsWindowObservationRevision)",
            "chrome=\(showsPlaybackChrome ? "on" : "off")",
            "windowOpacityTarget=\(windowPlaybackOpacity)",
            "windowInteractive=\(windowPlaybackAcceptsInput)",
            "videoVisible=\(playbackRuntime.presentationState == .videoVisible)",
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
            "windowStyle=automatic",
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
            "error=\((playbackRuntime.lastErrorMessage ?? "none").replacingOccurrences(of: ";", with: ","))"
        ]
        fields.append(contentsOf: rendererPerformanceAccessibilityFields(
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
            stereoLayout: playbackRuntime.effectiveStereoLayout
        )
    }

    private var windowPlaybackGeometryPolicy: WindowPlaybackGeometryPolicy {
        WindowPlaybackGeometryPolicy(
            presentation: hostedPlaybackPresentation,
            videoLayout: windowPlaybackLayout
        )
    }

    private func retryPlayback() {
        playbackRuntime.lastErrorMessage = nil
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
            withAnimation(.easeInOut(duration: 0.3)) {
                appModel.showControls = false
            }
        }
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
            "audioTrack=\(playbackRuntime.currentAudioTrackID ?? "none")",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)",
            "subtitleFrame=\(playbackRuntime.activeSubtitleFrame?.kind.rawValue ?? "none")",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "error=\((playbackRuntime.lastErrorMessage ?? "none").replacingOccurrences(of: ";", with: ","))"
        ]
        fields.append(contentsOf: rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        return fields.joined(separator: ";")
    }

    private var simulatedPresentation: String {
        return "none"
    }
}

#if os(visionOS)
enum SpatialPlaybackControlsScenePolicy {
    static func shouldHostControls(
        for presentation: PlaybackPresentation,
        isPanoramic: Bool
    ) -> Bool {
        _ = isPanoramic
        return presentation == .docked || presentation == .panorama
    }
}

struct SpatialPlaybackControlsRoot: View {
    let sceneIdentity: PlayerControlsSceneIdentity
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isStoppingPlayback = false

    private var hostedPresentation: PlaybackPresentation {
        guard let target = appModel.presentationTransition?.targetPresentation,
              target != .window else {
            return appModel.playbackPresentation
        }
        return target
    }

    private var controlsOpacity: Double {
        guard SpatialPlaybackControlsScenePolicy.shouldHostControls(
            for: hostedPresentation,
            isPanoramic: playbackRuntime.effectiveContentIsPanoramic
        ) else { return 0 }
        return PlaybackPresentationTransitionAppearance.playerControlsSceneHostOpacity(
            for: hostedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    private var controlsAcceptInput: Bool {
        SpatialPlaybackControlsScenePolicy.shouldHostControls(
            for: hostedPresentation,
            isPanoramic: playbackRuntime.effectiveContentIsPanoramic
        ) && appModel.showControls
            && PlaybackPresentationTransitionAppearance.acceptsInput(
            for: hostedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    var body: some View {
        WindowPlayerDeckView(
            presentationOverride: hostedPresentation,
            onExitPlayback: { Task { await stopSpatialPlayback() } }
        )
        .opacity(controlsOpacity)
        .animation(
            PlaybackPresentationTransitionAppearance.animation(
                for: controlsOpacity
            ),
            value: controlsOpacity
        )
        .allowsHitTesting(controlsAcceptInput)
        .disabled(isStoppingPlayback)
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { playbackRuntime.lastErrorMessage != nil },
                set: { if !$0 { playbackRuntime.lastErrorMessage = nil } }
            )
        ) {
            Button("Retry", action: retryPlayback)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("PlayerUI-spatialFailure-primary")
            Button("Close", role: .cancel) {
                Task { await stopSpatialPlayback() }
            }
            .accessibilityIdentifier("PlayerUI-spatialFailure-secondary")
        } message: {
            Text(playbackRuntime.lastErrorMessage ?? "Playback could not continue.")
        }
        .overlay {
            if ProcessInfo.processInfo.environment["ENCHRON_SPATIAL_ACCEPTANCE"] == "1" {
                Text("Spatial playback state")
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("PlayerUI-spatial-state")
                    .accessibilityValue(spatialAcceptanceValue)
            }
        }
        .background {
            SpatialPlatformEffectExecutor()
        }
        .onChange(of: playbackRuntime.effectiveContentIsPanoramic) { _, isPanoramic in
            guard hostedPresentation == .window,
                  isPanoramic == false else { return }
            dismissWindow(id: "playerControls", value: sceneIdentity)
        }
        .onChange(of: appModel.showControls) { _, isVisible in
            guard isVisible == false else { return }
            // Mirrors the immersive-side rule: no scene operations while a
            // presentation transition is in flight; the transition-end sync
            // in ImmersiveSpaceView performs the deferred dismissal.
            guard appModel.presentationTransition == nil else { return }
            dismissWindow(id: "playerControls", value: sceneIdentity)
        }
        .onChange(of: appModel.activePlayerControlsSceneIdentity) { _, activeIdentity in
            guard activeIdentity != sceneIdentity else { return }
            dismissWindow(id: "playerControls", value: sceneIdentity)
        }
        }

    private var spatialAcceptanceValue: String {
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
        let environment = environmentAccessibilityValues(
            for: appModel.environmentContext
        )
        let panoramaReturnEnvironment = environmentAccessibilityValues(
            for: appModel.panoramaReturnEnvironmentContext
        )
        let immersionAmount = appModel.lastObservedImmersionAmount.map {
            String($0)
        } ?? "none"
        let skyboxOpacity = appModel.environmentSkyboxOpacity.map {
            String(format: "%.4f", $0)
        } ?? "none"
        var fields: [String] = [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "transition=\(appModel.presentationTransition?.targetPresentation.rawValue ?? "none")",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "controlsInteractive=\(controlsAcceptInput)",
            "controlsOpacityTarget=\(controlsOpacity)",
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
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "rendererConsumer=\(playbackRuntime.rendererConsumerPresentation?.rawValue ?? "none")",
            "rendererConsumerEntity=\(playbackRuntime.rendererConsumerEntityID == nil ? "none" : "present")",
            "playbackEntity=\(playbackVideoEntityStore.entityID)",
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
            "providerCodecName=\(debugSnapshot?.providerOpen?.codecName ?? "none")",
            "providerCodecTag=\(debugSnapshot?.providerOpen?.codecTag ?? "none")",
            "providerCodecConfiguration=\(debugSnapshot?.providerOpen?.codecConfigurationSummary.value ?? "none")",
            "sampleMediaSubtype=\(debugSnapshot?.lastVideoSample?.mediaSubtype ?? "none")",
            "providerTransferFunction=\(providerTransferFunction)",
            "sampleTransferFunction=\(sampleTransferFunction)",
            "sampleHasDvcC=\(debugSnapshot?.lastVideoSample?.formatSignaling.dvcC.value.map(String.init) ?? "none")",
            "sampleHasDvvC=\(debugSnapshot?.lastVideoSample?.formatSignaling.dvvC.value.map(String.init) ?? "none")",
            "formatProvenance=\(playbackRuntime.activeMediaFormatProvenance.rawValue)",
            "sourceContentKind=\(playbackRuntime.sourceVideoContentKind.rawValue)",
            "projection=\(playbackRuntime.effectiveProjectionType.rawValue)",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "mvHEVC=\(playbackRuntime.diagnostics.isMVHEVC)",
            "effectiveContentIsPanoramic=\(playbackRuntime.effectiveContentIsPanoramic)",
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
            "subtitleTracks=\(playbackRuntime.availableSubtitleTracks.count)",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)",
            "screenScale=\(String(format: "%.4f", appModel.screenScale))",
            "screenDistance=\(String(format: "%.4f", appModel.screenDepthOffset))",
            "screenElevation=\(String(format: "%.4f", appModel.screenViewAngle))",
            "registeredPlatformExecutorCount=\(spatialPlatformEffectCoordinator.registeredPlatformExecutorCount)",
            "lastPlatformOperation=\(spatialPlatformEffectCoordinator.lastPlatformOperation)",
            "mainWindowObservedResidency=\(spatialPlatformEffectCoordinator.mainWindowObservedResidency)",
            "mainWindowObservationRevision=\(spatialPlatformEffectCoordinator.mainWindowObservationRevision)",
            "playerControlsWindowResidency=\(spatialPlatformEffectCoordinator.playerControlsWindowObservedResidency)",
            "playerControlsWindowObservationRevision=\(spatialPlatformEffectCoordinator.playerControlsWindowObservationRevision)"
        ]
        fields.append(contentsOf: rendererPerformanceAccessibilityFields(
            playbackRuntime.diagnostics
        ))
        return (fields + appModel.spatialPlaybackSurfaceObservation.accessibilityFields)
            .joined(separator: ";")
    }

    @MainActor
    private func stopSpatialPlayback() async {
        guard isStoppingPlayback == false else { return }
        isStoppingPlayback = true
        defer { isStoppingPlayback = false }

        await playbackLauncher.stopPlaybackAndWait()
        appModel.requestStoppedPlaybackCleanup()
    }

    private func retryPlayback() {
        playbackRuntime.lastErrorMessage = nil
        playbackLauncher.retryPlayback()
    }

}

private func rendererPerformanceAccessibilityFields(
    _ diagnostics: PlaybackDiagnostics
) -> [String] {
    [
        "sourceFrameRate=\(diagnostics.nominalFrameRate)",
        "rendererTotalFrames=\(diagnostics.rendererTotalFrameCount.map { String($0) } ?? "none")",
        "rendererDroppedFrames=\(diagnostics.rendererDroppedFrameCount.map { String($0) } ?? "none")",
        "rendererCorruptedFrames=\(diagnostics.rendererCorruptedFrameCount.map { String($0) } ?? "none")",
        "rendererOptimizedFrames=\(diagnostics.rendererOptimizedCompositingFrameCount.map { String($0) } ?? "none")",
        "rendererAccumulatedFrameDelay=\(diagnostics.rendererAccumulatedFrameDelaySeconds.map { String($0) } ?? "none")",
        "rendererMetricsObservations=\(diagnostics.rendererPerformanceMetricsObservationCount)",
    ]
}

private func environmentAccessibilityValues(
    for context: EnvironmentContext?
) -> (environment: String, effect: String) {
    switch context {
    case nil:
        ("inactive", "none")
    case .some(.none):
        ("none", "none")
    case .some(.active(let environment, let effect)):
        (environment.rawValue, effect?.rawValue ?? "none")
    }
}
#endif
