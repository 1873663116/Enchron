import OSLog
import SwiftUI

private let macPresentationLogger = Logger(
    subsystem: "app.enchron",
    category: "MacPresentationHost"
)

enum MacPlaybackPresentationHost {
    static func surfacePresentation(
        for productPresentation: PlaybackPresentation
    ) -> PlaybackPresentation {
        productPresentation == .docked ? .docked : .window
    }

    static func simulatedPresentation(
        productPresentation: PlaybackPresentation,
        surfacePresentation: PlaybackPresentation
    ) -> PlaybackPresentation? {
        productPresentation == surfacePresentation ? nil : productPresentation
    }
}

struct EnchronMacOSProductRoot: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    @State private var visiblePresentation: PlaybackPresentation = .window
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        MainView(macOSPlaybackPresentation: visiblePresentation)
        .onChange(of: appModel.presentationTransition?.id) { _, _ in
            transitionTask?.cancel()
            guard let transition = appModel.presentationTransition else { return }
            transitionTask = Task { await complete(transition) }
        }
        .onChange(of: playbackRuntime.hasActivePlaybackRequest) { _, isActive in
            guard isActive == false else { return }
            transitionTask?.cancel()
            transitionTask = nil
            visiblePresentation = .window
            appModel.resetPlaybackPresentationForStoppedPlayback()
            macPresentationLogger.notice("playback stopped; host restored window presentation")
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }

    @MainActor
    private func complete(_ transition: PlaybackPresentationTransition) async {
        guard Task.isCancelled == false,
              playbackRuntime.hasActivePlaybackRequest else {
            appModel.resetPlaybackPresentationForStoppedPlayback()
            visiblePresentation = .window
            return
        }
        guard appModel.isTransitioningPlaybackPresentation == false else { return }

        appModel.isTransitioningPlaybackPresentation = true
        defer { appModel.isTransitioningPlaybackPresentation = false }

        let previousSurfacePresentation = visiblePresentation
        let targetSurfacePresentation = MacPlaybackPresentationHost.surfacePresentation(
            for: transition.targetPresentation
        )
        macPresentationLogger.notice(
            "transition begin from=\(transition.previousPresentation.rawValue, privacy: .public) to=\(transition.targetPresentation.rawValue, privacy: .public) hosted=\(targetSurfacePresentation.rawValue, privacy: .public)"
        )
        visiblePresentation = targetSurfacePresentation
        await Task.yield()
        guard Task.isCancelled == false else { return }

        let attached = await playbackRuntime.waitUntilAttached(to: targetSurfacePresentation)
        guard Task.isCancelled == false else { return }
        guard attached else {
            macPresentationLogger.error(
                "transition attach timed out target=\(transition.targetPresentation.rawValue, privacy: .public) hosted=\(targetSurfacePresentation.rawValue, privacy: .public)"
            )
            await restore(previousSurfacePresentation)
            appModel.rollbackPlaybackPresentation(transition.id)
            playbackRuntime.lastErrorMessage = "The macOS RealityView surface could not attach to PlaybackCore."
            return
        }

        do {
            try appModel.commitPlaybackPresentation(transition.id)
            macPresentationLogger.notice(
                "transition committed presentation=\(transition.targetPresentation.rawValue, privacy: .public) hosted=\(targetSurfacePresentation.rawValue, privacy: .public) simulated=\(transition.targetPresentation == .panorama, privacy: .public) session=\(playbackRuntime.activeSessionID ?? "none", privacy: .public)"
            )
        } catch {
            macPresentationLogger.error(
                "transition commit failed error=\(error.localizedDescription, privacy: .public)"
            )
            await restore(previousSurfacePresentation)
            appModel.rollbackPlaybackPresentation(transition.id)
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func restore(_ presentation: PlaybackPresentation) async {
        macPresentationLogger.notice(
            "transition restoring presentation=\(presentation.rawValue, privacy: .public)"
        )
        visiblePresentation = presentation
        await Task.yield()
        _ = await playbackRuntime.waitUntilAttached(to: presentation)
    }
}
