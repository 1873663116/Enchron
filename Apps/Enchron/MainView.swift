import DesignSystem
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

enum PlaybackSurfaceMountPolicy {
    static func shouldMount(showsWindowPlayback: Bool) -> Bool {
        showsWindowPlayback
    }
}

public struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher

    @State private var controlsTimer: Task<Void, Never>?
    private let playbackSurfaceIsEnabled: Bool
    private let macOSPlaybackPresentation: PlaybackPresentation

    public init(
        playbackSurfaceIsEnabled: Bool = true,
        macOSPlaybackPresentation: PlaybackPresentation = .window
    ) {
        self.playbackSurfaceIsEnabled = playbackSurfaceIsEnabled
        self.macOSPlaybackPresentation = macOSPlaybackPresentation
    }

    private var showsWindowPlayback: Bool {
        #if os(macOS)
        playbackRuntime.hasActivePlaybackRequest && macOSPlaybackPresentation != .panorama
        #else
        playbackRuntime.hasActivePlaybackRequest
            && (appModel.playbackPresentation == .window
                || appModel.presentationTransition?.targetPresentation == .window)
        #endif
    }

    private var windowSurfaceIsActive: Bool {
        #if os(macOS)
        playbackSurfaceIsEnabled
            && showsWindowPlayback
        #else
        playbackSurfaceIsEnabled
            && showsWindowPlayback
            && (appModel.presentationTransition == nil
                || appModel.presentationTransition?.targetPresentation == .window)
        #endif
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
        #if os(visionOS)
        .background {
            SpatialPlatformEffectExecutor()
        }
        #endif
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(visionOS)
        primaryContent
            .ornament(
                visibility: playbackRuntime.hasActivePlaybackRequest ? .hidden : .visible,
                attachmentAnchor: .scene(.leading),
                contentAlignment: .trailing
            ) {
                NavigationOrnament()
            }
            .ornament(
                visibility: showsWindowPlayback && appModel.showControls
                    ? .visible
                    : .hidden,
                attachmentAnchor: .scene(.bottom)
            ) {
                WindowPlayerDeckView(presentationOverride: .window)
                    .accessibilityIdentifier("PlayerUI-window-controls-ornament")
            }
        #else
        ZStack(alignment: .leading) {
            primaryContent
            if playbackRuntime.hasActivePlaybackRequest == false {
                NavigationOrnament()
                    .padding(.leading, DesignTokens.Spacing.md)
            }
        }
        .overlay(alignment: .bottom) {
            if showsWindowPlayback && appModel.showControls {
                WindowPlayerDeckView(presentationOverride: .window)
                    .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
        #endif
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
        #if os(visionOS)
        browser
            .glassBackgroundEffect(in: ContainerRelativeShape())
        #else
        browser
        #endif
    }

    @ViewBuilder
    private var browser: some View {
        switch appModel.selectedTab {
        case .files: FilesScreen()
        case .settings: SettingsScreen()
        case .environment:
            #if os(macOS)
            MacEnvironmentSceneHostView()
            #else
            Color.clear
            #endif
        }
    }

    @ViewBuilder
    private var windowPlayback: some View {
        WindowPlaybackRootView(
            layout: windowPlaybackLayout,
            showsWindowChrome: appModel.showControls
                && hostedPlaybackPresentation == .window
        ) {
            windowPlaybackCanvas
        } topChrome: {
            PlayerInfoBarView()
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("PlayerUI-window-top-overlay")
        } mediaFacts: {
            PlayerMediaInfoView()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("PlayerUI-window-media-overlay")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-window-control-plane")
        .accessibilityValue(windowPlaybackStateValue)
    }

    private var windowPlaybackCanvas: some View {
        ZStack {
            PlaybackVideoSurface(
                presentation: hostedPlaybackPresentation,
                isActive: windowSurfaceIsActive
            )

            if playbackRuntime.presentationState == .placeholder || playbackRuntime.lifecycle == .loading {
                ProgressView()
                    .controlSize(.large)
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
        let position = playbackRuntime.playbackPosition
        return [
            "active=\(playbackRuntime.hasActivePlaybackRequest)",
            "formatReady=\(playbackRuntime.mediaFormatIsKnown)",
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)"
        ].joined(separator: ";")
    }

    private var hostedPlaybackPresentation: PlaybackPresentation {
        #if os(macOS)
        macOSPlaybackPresentation
        #else
        .window
        #endif
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
        return [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "hosted=\(hostedPresentation.rawValue)",
            "simulation=\(simulatedPresentation)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "audioTrack=\(playbackRuntime.currentAudioTrackID ?? "none")",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)",
            "subtitleFrame=\(playbackRuntime.activeSubtitleFrame?.kind.rawValue ?? "none")",
            "controls=\(appModel.showControls ? "shown" : "hidden")",
            "error=\((playbackRuntime.lastErrorMessage ?? "none").replacingOccurrences(of: ";", with: ","))"
        ].joined(separator: ";")
    }

    private var simulatedPresentation: String {
        #if os(macOS)
        if appModel.playbackPresentation == .panorama,
           hostedPresentation == .window {
            return PlaybackPresentation.panorama.rawValue
        }
        #endif
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
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isStoppingPlayback = false

    private var shouldHostControls: Bool {
        SpatialPlaybackControlsScenePolicy.shouldHostControls(
            for: appModel.playbackPresentation
        )
    }

    var body: some View {
        WindowPlayerDeckView(
            onExitPlayback: { Task { await stopSpatialPlayback() } }
        )
        .opacity(shouldHostControls ? 1 : 0)
        .allowsHitTesting(shouldHostControls)
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
        .onChange(of: shouldHostControls, initial: true) { _, shouldHost in
            guard shouldHost == false else { return }
            dismissWindow(id: "playerControls")
        }
    }

    private var spatialAcceptanceValue: String {
        let position = playbackRuntime.playbackPosition
        return [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "screenScale=\(String(format: "%.2f", appModel.screenScale))"
        ].joined(separator: ";")
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
#endif
