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

enum PlaybackPresentationRendererBindingPolicy {
    static func shouldBindRenderer(
        for presentation: PlaybackPresentation,
        previousPresentation: PlaybackPresentation?,
        targetPresentation: PlaybackPresentation?,
        sourceRendererMayRelease: Bool
    ) -> Bool {
        guard let previousPresentation,
              let targetPresentation,
              previousPresentation != targetPresentation else {
            return true
        }

        guard previousPresentation == .window || targetPresentation == .window else {
            return true
        }
        if presentation == previousPresentation {
            return sourceRendererMayRelease == false
        }
        if presentation == targetPresentation {
            return sourceRendererMayRelease
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
        transition: PlaybackPresentationTransition?
    ) -> Double {
        if let transition {
            return hostedPresentation == transition.targetPresentation
                ? targetPreparationOpacity
                : 0
        }
        return hostedPresentation == settledPresentation ? 1 : 0
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
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator

    @State private var controlsTimer: Task<Void, Never>?
    @State private var reapplyVerificationSnapshotTick = 0
    private let playbackSurfaceIsEnabled: Bool

    public init(playbackSurfaceIsEnabled: Bool = true) {
        self.playbackSurfaceIsEnabled = playbackSurfaceIsEnabled
    }

    private var showsWindowPlayback: Bool {
        playbackRuntime.hasActivePlaybackRequest
            && (appModel.playbackPresentation == .window
                || appModel.presentationTransition?.targetPresentation == .window)
    }

    private var windowSurfaceIsActive: Bool {
        let transition = appModel.presentationTransition
        return playbackSurfaceIsEnabled
            && showsWindowPlayback
            && PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
                for: .window,
                previousPresentation: transition?.previousPresentation,
                targetPresentation: transition?.targetPresentation,
                sourceRendererMayRelease:
                    appModel.presentationSourceRendererMayRelease
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
        }
        .onChange(of: playbackRuntime.hasActivePlaybackRequest) { _, hasActivePlaybackRequest in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                if hasActivePlaybackRequest {
                    scheduleControlsAutoHide()
                } else {
                    controlsTimer?.cancel()
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
        #if os(visionOS)
        .background {
            SpatialPlatformEffectExecutor()
        }
        #endif
    }

    /// Player Controls and top chrome only after presentable video is up.
    private var showsPlaybackChrome: Bool {
        let chrome =
            showsWindowPlayback
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
                WindowPlayerDeckView(presentationOverride: .window)
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
                PlaybackOverlayCard(
                    systemImage: "clock.arrow.circlepath",
                    title: "Resume Playback?",
                    message: "Continue from \(PlaybackTimeFormatter.clock(decision.seconds)) or start from the beginning.",
                    primaryTitle: "Resume",
                    primaryIcon: "play.fill",
                    primaryAction: playbackLauncher.resumePendingPlayback,
                    secondaryTitle: "Start Over",
                    secondaryIcon: "backward.end.fill",
                    secondaryAction: playbackLauncher.startPendingPlaybackFromBeginning,
                    identifierPrefix: "PlayerUI-resume"
                )
            }
        }
    }

    @ViewBuilder
    private var browserWindowSurface: some View {
        if playbackRuntime.hasActivePlaybackRequest {
            Color.clear
        } else {
            browser
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
            layout: windowPlaybackLayout,
            showsWindowChrome: showsPlaybackChrome
                && hostedPlaybackPresentation == .window,
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
            PlayerInfoBarView()
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

            if let message = playbackRuntime.lastErrorMessage {
                PlaybackOverlayCard(
                    systemImage: "exclamationmark.triangle",
                    title: "Failed to Load",
                    message: message,
                    primaryTitle: "Retry",
                    primaryIcon: "arrow.clockwise",
                    primaryAction: retryPlayback,
                    secondaryTitle: "Close",
                    secondaryIcon: "xmark",
                    secondaryAction: playbackLauncher.stopPlayback,
                    identifierPrefix: "PlayerUI-loadFailure"
                )
            }
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
        let sourceRemovalToTargetBindSeconds =
            playbackRuntime.sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds
            .map { String(format: "%.3f", $0) } ?? "none"
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
            "windowPortalToProgressiveChangeConfirmed=\(appModel.windowPortalToProgressiveChangeIsConfirmed)",
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
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "rendererConsumer=\(playbackRuntime.rendererConsumerPresentation?.rawValue ?? "none")",
            "rendererConsumerEntity=\(playbackRuntime.rendererConsumerEntityID == nil ? "none" : "present")",
            "sourceRemovalToTargetBindSeconds=\(sourceRemovalToTargetBindSeconds)",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "chrome=\(showsPlaybackChrome ? "on" : "off")",
            "secondaryMenu=\(appModel.isPlaybackSecondaryMenuPresented ? "open" : "closed")",
            "windowOpacityTarget=\(windowPlaybackOpacity)",
            "windowInteractive=\(windowPlaybackAcceptsInput)",
            "videoVisible=\(playbackRuntime.presentationState == .videoVisible)",
            "projection=\(playbackRuntime.effectiveProjectionType.rawValue)",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "windowStyle=automatic",
            "loadingSpinner=\(loadingSpinnerVisible ? "on" : "off")",
            "tapTrace=\(appModel.debugSurfaceTapTrace)",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "streamEpoch=\(output.streamEpoch)",
            "videoSamples=\(output.videoSampleCount)",
            "rendererInputs=\(output.acceptedRendererInputCount)",
            "lastRendererInputEpoch=\(lastRendererInputEpoch)",
            "lastRendererInputGraphRevision=\(lastRendererInputGraphRevision)",
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
        .window
    }

    private var isLeavingWindowPresentation: Bool {
        appModel.presentationTransition?.previousPresentation == .window
            && appModel.presentationTransition?.targetPresentation != .window
    }

    private var windowPlaybackOpacity: Double {
        PlaybackPresentationTransitionAppearance.opacity(
            for: .window,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    private var windowPlaybackAcceptsInput: Bool {
        PlaybackPresentationTransitionAppearance.acceptsInput(
            for: .window,
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
        let displayedFrameObservations = (
            debugSnapshot?.rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let outputBoundary = PlaybackOutputVerification.firstIncompleteBoundary(
            current: output
        )
        return [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "hosted=\(hostedPresentation.rawValue)",
            "simulation=\(simulatedPresentation)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "streamEpoch=\(output.streamEpoch)",
            "videoSamples=\(output.videoSampleCount)",
            "rendererInputs=\(output.acceptedRendererInputCount)",
            "lastRendererInputEpoch=\(lastRendererInputEpoch)",
            "lastRendererInputGraphRevision=\(lastRendererInputGraphRevision)",
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
        ].joined(separator: ";")
    }

    private var simulatedPresentation: String {
        return "none"
    }
}

#if os(visionOS)
enum SpatialPlaybackControlsScenePolicy {
    static func shouldHostControls(
        for presentation: PlaybackPresentation
    ) -> Bool {
        presentation != .window
    }
}

struct SpatialPlaybackControlsRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(SpatialPlatformEffectCoordinator.self)
    private var spatialPlatformEffectCoordinator
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
            for: hostedPresentation
        ), appModel.presentationTransition == nil,
          appModel.showControls else { return 0 }
        return PlaybackPresentationTransitionAppearance.opacity(
            for: hostedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    private var controlsAcceptInput: Bool {
        SpatialPlaybackControlsScenePolicy.shouldHostControls(
            for: hostedPresentation
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
        .overlay {
            if let message = playbackRuntime.lastErrorMessage {
                PlaybackOverlayCard(
                    systemImage: "exclamationmark.triangle",
                    title: "Playback Error",
                    message: message,
                    primaryTitle: "Retry",
                    primaryIcon: "arrow.clockwise",
                    primaryAction: retryPlayback,
                    secondaryTitle: "Close",
                    secondaryIcon: "xmark",
                    secondaryAction: { Task { await stopSpatialPlayback() } },
                    identifierPrefix: "PlayerUI-spatialFailure"
                )
            }
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
    }

    private var spatialAcceptanceValue: String {
        let position = playbackRuntime.playbackPosition
        let output = playbackRuntime.outputObservation()
        let debugSnapshot = playbackRuntime.debugSnapshot()
        let lastRendererInputEpoch = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.streamEpoch) } ?? "none"
        let lastRendererInputGraphRevision = debugSnapshot?.lastAcceptedRendererInput
            .map { String($0.graphRevision) } ?? "none"
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
        let sourceRemovalToTargetBindSeconds =
            playbackRuntime.sourceVideoPlayerComponentRemovalToTargetVideoPlayerComponentBindSeconds
            .map { String(format: "%.3f", $0) } ?? "none"
        let fields: [String] = [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "transition=\(appModel.presentationTransition?.targetPresentation.rawValue ?? "none")",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "controlsInteractive=\(controlsAcceptInput)",
            "controlsOpacityTarget=\(controlsOpacity)",
            "sourceRendererMayRelease=\(appModel.presentationSourceRendererMayRelease)",
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
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "rendererConsumer=\(playbackRuntime.rendererConsumerPresentation?.rawValue ?? "none")",
            "rendererConsumerEntity=\(playbackRuntime.rendererConsumerEntityID == nil ? "none" : "present")",
            "sourceRemovalToTargetBindSeconds=\(sourceRemovalToTargetBindSeconds)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "streamEpoch=\(output.streamEpoch)",
            "videoSamples=\(output.videoSampleCount)",
            "rendererInputs=\(output.acceptedRendererInputCount)",
            "lastRendererInputEpoch=\(lastRendererInputEpoch)",
            "lastRendererInputGraphRevision=\(lastRendererInputGraphRevision)",
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
            "mainWindowObservationRevision=\(spatialPlatformEffectCoordinator.mainWindowObservationRevision)"
        ]
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

private func environmentAccessibilityValues(
    for context: EnvironmentContext?
) -> (environment: String, effect: String) {
    switch context {
    case nil:
        ("inactive", "none")
    case .some(.none):
        ("none", "none")
    case .some(.active(let environment, let effect)):
        (environment.rawValue, effect.rawValue)
    }
}
#endif
