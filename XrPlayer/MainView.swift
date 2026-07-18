import PlaybackCore
import SwiftUI
#if os(visionOS)
import UIKit
#endif

enum PlaybackSurfaceMountPolicy {
    static func shouldMount(showsWindowPlayback: Bool) -> Bool {
        showsWindowPlayback
    }
}

public struct MainView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

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
        playbackRuntime.hasActivePlaybackRequest && appModel.playbackPresentation == .window
        #endif
    }

    private var windowSurfaceIsActive: Bool {
        #if os(macOS)
        playbackSurfaceIsEnabled
            && showsWindowPlayback
        #else
        playbackSurfaceIsEnabled
            && showsWindowPlayback
            && appModel.presentationTransition == nil
        #endif
    }

    public var body: some View {
        platformContent
        .onAppear {
            playbackRuntime.onPlaybackEnded = {
                let showControls = playbackLauncher.handlePlaybackEnded()
                if showControls {
                    appModel.showControls = true
                    controlsTimer?.cancel()
                }
            }
        }
        .onChange(of: playbackRuntime.hasActivePlaybackRequest) { _, hasActivePlaybackRequest in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                updateWindowResizingRestrictions(isPlaying: hasActivePlaybackRequest)
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
        .onChange(of: appModel.presentationTransition?.id) { _, _ in
            #if os(visionOS)
            guard let transition = appModel.presentationTransition,
                  transition.targetPresentation != .window else { return }
            Task { await enterSpatialPresentation(transition) }
            #endif
        }
        .onChange(of: appModel.immersiveSpaceRequest) { _, request in
            #if os(visionOS)
            guard let request else { return }
            appModel.immersiveSpaceRequest = nil
            Task {
                switch request {
                case .open: await openEnvironmentPreview()
                case .dismiss: await closeEnvironmentPreview()
                }
            }
            #endif
        }
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
        #else
        ZStack(alignment: .leading) {
            primaryContent
            if playbackRuntime.hasActivePlaybackRequest == false {
                NavigationOrnament()
                    .padding(.leading, DesignTokens.Spacing.md)
            }
        }
        #endif
    }

    private var primaryContent: some View {
        ZStack {
            browser
                .opacity(showsWindowPlayback ? 0 : 1)
                .allowsHitTesting(!showsWindowPlayback)

            if PlaybackSurfaceMountPolicy.shouldMount(
                showsWindowPlayback: showsWindowPlayback
            ) {
                windowPlayback
            }

            if ProcessInfo.processInfo.environment["ENCHRON_AUTOMATION_PROBE"] == "1",
               playbackRuntime.hasActivePlaybackRequest {
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
        WindowPlaybackPageLayout(spacing: DesignTokens.Spacing.md) {
            windowPlaybackCanvasWithTopBar

            if appModel.showControls {
                WindowPlayerDeckView()
                    .accessibilityIdentifier("PlayerUI-window-playback-deck")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-window-control-plane")
        .accessibilityValue(windowPlaybackStateValue)
    }

    private var windowPlaybackCanvasWithTopBar: some View {
        windowPlaybackCanvas
            .overlay(alignment: .top) {
                if appModel.showControls, hostedPlaybackPresentation == .window {
                    PlayerInfoBarView()
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("PlayerUI-window-top-overlay")
                }
            }
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

    private func retryPlayback() {
        playbackRuntime.lastErrorMessage = nil
        guard let request = playbackRuntime.currentLaunchRequest else { return }
        playbackLauncher.beginPlayback(request)
    }

    #if os(visionOS)
    @MainActor
    private func enterSpatialPresentation(_ transition: PlaybackPresentationTransition) async {
        guard appModel.isTransitioningPlaybackPresentation == false else { return }
        appModel.isTransitioningPlaybackPresentation = true
        let reusedEnvironmentSpace = appModel.immersiveSpaceState == .open
            && appModel.isEnvironmentImmersiveActive
        if reusedEnvironmentSpace == false {
            appModel.immersiveSpaceState = .inTransition
        }
        appModel.isEnvironmentImmersiveActive = false
        appModel.isFullImmersion = true
        await Task.yield()

        let opened: Bool
        if reusedEnvironmentSpace {
            opened = true
        } else {
            if case .opened = await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                opened = true
            } else {
                opened = false
            }
        }

        guard opened else {
            appModel.rollbackPlaybackPresentation(transition.id)
            appModel.immersiveSpaceState = .closed
            appModel.isEnvironmentImmersiveActive = false
            appModel.isTransitioningPlaybackPresentation = false
            return
        }

        guard await playbackRuntime.waitUntilAttached(to: transition.targetPresentation) else {
            if reusedEnvironmentSpace {
                appModel.isEnvironmentImmersiveActive = true
                appModel.isFullImmersion = false
            } else {
                await dismissImmersiveSpace()
                appModel.immersiveSpaceState = .closed
            }
            appModel.rollbackPlaybackPresentation(transition.id)
            playbackRuntime.lastErrorMessage = "The spatial playback surface could not attach to PlaybackCore."
            appModel.isTransitioningPlaybackPresentation = false
            return
        }

        do {
            try appModel.commitPlaybackPresentation(transition.id)
            appModel.immersiveSpaceState = .open
            openWindow(id: "playerControls")
            dismissWindow(id: "main")
        } catch {
            if reusedEnvironmentSpace {
                appModel.isEnvironmentImmersiveActive = true
                appModel.isFullImmersion = false
            } else {
                await dismissImmersiveSpace()
                appModel.immersiveSpaceState = .closed
            }
            appModel.rollbackPlaybackPresentation(transition.id)
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
        appModel.isTransitioningPlaybackPresentation = false
    }

    @MainActor
    private func openEnvironmentPreview() async {
        guard appModel.immersiveSpaceState == .closed else { return }
        appModel.immersiveSpaceState = .inTransition
        appModel.isFullImmersion = false
        if case .opened = await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            appModel.immersiveSpaceState = .open
            appModel.isEnvironmentImmersiveActive = true
            try? appModel.updateEnvironmentContext(.active(appModel.currentCinemaEnvironment))
        } else {
            appModel.immersiveSpaceState = .closed
        }
    }

    @MainActor
    private func closeEnvironmentPreview() async {
        guard appModel.immersiveSpaceState == .open else { return }
        await dismissImmersiveSpace()
        appModel.immersiveSpaceState = .closed
        appModel.isEnvironmentImmersiveActive = false
        try? appModel.updateEnvironmentContext(.none)
    }
    #endif

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

    private func updateWindowResizingRestrictions(isPlaying: Bool) {
        #if os(visionOS)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        windowScene.requestGeometryUpdate(
            .Vision(resizingRestrictions: isPlaying ? .uniform : .freeform)
        )
        #endif
    }
}

private struct WindowPlaybackPageLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let canvas = subviews.first else { return }
        let deck = subviews.count > 1 ? subviews[1] : nil
        let deckSize = deck?.sizeThatFits(
            ProposedViewSize(width: bounds.width, height: nil)
        )
        let geometry = WindowPlaybackPageGeometry.resolve(
            in: bounds.size,
            deckSize: deckSize,
            spacing: spacing
        )

        canvas.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(geometry.canvasFrame.size)
        )
        if let deck, let deckFrame = geometry.deckFrame {
            deck.place(
                at: CGPoint(x: bounds.minX + deckFrame.minX, y: bounds.minY + deckFrame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(deckFrame.size)
            )
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
            "controls=\(appModel.showControls ? "shown" : "hidden")"
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
struct SpatialPlaybackControlsRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isStoppingPlayback = false

    var body: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
            Button {
                Task { await stopSpatialPlayback() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Stop Playback")
            .accessibilityHint("Stops playback and returns to the browser")
            .accessibilityIdentifier("PlayerUI-spatial-button-stop")
            .disabled(isStoppingPlayback)

            WindowPlayerDeckView()
        }
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
        .accessibilityIdentifier("PlayerUI-spatial-control-plane")
        .accessibilityValue(spatialAcceptanceValue)
        .onChange(of: appModel.presentationTransition?.id) { _, _ in
            guard let transition = appModel.presentationTransition,
                  transition.targetPresentation == .window else { return }
            Task { await returnToWindow(transition) }
        }
        .onChange(of: appModel.immersiveSpaceState) { _, state in
            guard state == .closed,
                  appModel.playbackPresentation != .window,
                  appModel.presentationTransition == nil else { return }
            recoverFromSystemDismissal()
        }
    }

    private var spatialAcceptanceValue: String {
        guard ProcessInfo.processInfo.environment["ENCHRON_SPATIAL_ACCEPTANCE"] == "1" else {
            return ""
        }
        return [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "screenScale=\(String(format: "%.2f", appModel.screenScale))"
        ].joined(separator: ";")
    }

    @MainActor
    private func stopSpatialPlayback() async {
        guard isStoppingPlayback == false else { return }
        isStoppingPlayback = true
        defer { isStoppingPlayback = false }

        await playbackLauncher.stopPlaybackAndWait()
        appModel.resetPlaybackPresentationForStoppedPlayback()
        appModel.isEnvironmentImmersiveActive = false
        appModel.isFullImmersion = false
        await dismissImmersiveSpace()
        appModel.immersiveSpaceState = .closed
        openWindow(id: "main")
        dismissWindow(id: "playerControls")
    }

    private func retryPlayback() {
        guard let request = playbackRuntime.currentLaunchRequest else { return }
        playbackRuntime.lastErrorMessage = nil
        playbackLauncher.beginPlayback(request)
    }

    @MainActor
    private func returnToWindow(_ transition: PlaybackPresentationTransition) async {
        guard appModel.isTransitioningPlaybackPresentation == false else { return }
        appModel.isTransitioningPlaybackPresentation = true
        playbackRuntime.detach()
        let keepsEnvironmentOpen = transition.targetEnvironment.environment != nil
        if keepsEnvironmentOpen {
            appModel.isEnvironmentImmersiveActive = true
            appModel.isFullImmersion = false
            await Task.yield()
        } else {
            await dismissImmersiveSpace()
        }
        do {
            try appModel.commitPlaybackPresentation(transition.id)
            appModel.immersiveSpaceState = keepsEnvironmentOpen ? .open : .closed
            openWindow(id: "main")
            dismissWindow(id: "playerControls")
        } catch {
            appModel.rollbackPlaybackPresentation(transition.id)
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
        appModel.isTransitioningPlaybackPresentation = false
    }

    @MainActor
    private func recoverFromSystemDismissal() {
        do {
            let transition = try appModel.requestPlaybackPresentation(.window)
            try appModel.commitPlaybackPresentation(transition.id)
            try appModel.updateEnvironmentContext(.none)
            appModel.isEnvironmentImmersiveActive = false
            openWindow(id: "main")
            dismissWindow(id: "playerControls")
        } catch {
            if let transition = appModel.presentationTransition {
                appModel.rollbackPlaybackPresentation(transition.id)
            }
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }
}
#endif
