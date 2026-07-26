import Foundation
import OSLog
import PlaybackPresentation
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
        .onChange(of: appModel.pendingSpatialPlatformEffect?.id) { _, _ in
            transitionTask?.cancel()
            guard let request = appModel.pendingSpatialPlatformEffect else { return }
            let executionID = UUID()
            transitionTask = Task {
                await complete(request, executionID: executionID)
            }
        }
        .onChange(of: playbackRuntime.hasActivePlaybackRequest) { _, isActive in
            guard isActive == false else { return }
            transitionTask?.cancel()
            transitionTask = nil
            visiblePresentation = .window
            appModel.requestStoppedPlaybackCleanup()
            macPresentationLogger.notice("playback stopped; host restored window presentation")
        }
        .onDisappear {
            transitionTask?.cancel()
        }
    }

    @MainActor
    private func complete(
        _ request: SpatialPlatformEffectRequest,
        executionID: UUID
    ) async {
        guard appModel.claimSpatialPlatformEffect(
            request.id,
            executionID: executionID
        ) else { return }
        if let mediaSessionID = request.playbackTransportPlan?.mediaSessionID,
           playbackRuntime.activeSessionID != mediaSessionID {
            finish(
                request,
                executionID: executionID,
                outcome: .failed(.mediaSessionChanged),
                performsAfterTransport: false
            )
            return
        }
        if let beforeEffect = request.playbackTransportPlan?.beforeEffect {
            do {
                try playbackRuntime.performSpatialPlaybackTransport(beforeEffect)
            } catch {
                playbackRuntime.lastErrorMessage = error.localizedDescription
                let failure: SpatialPlatformEffectFailure =
                    playbackRuntime.activeSessionID == beforeEffect.mediaSessionID
                        ? .playbackPauseFailed
                        : .mediaSessionChanged
                finish(
                    request,
                    executionID: executionID,
                    outcome: .failed(failure),
                    performsAfterTransport: false
                )
                return
            }
        }
        if case .normalizeStoppedSpatialPlayback = request.effect {
            visiblePresentation = .window
            finish(request, executionID: executionID, outcome: .succeeded)
            return
        }
        if case .recoverSpatialPlayback = request.effect {
            visiblePresentation = .window
            finish(
                request,
                executionID: executionID,
                outcome: .failed(.executionCancelled)
            )
            return
        }
        guard Task.isCancelled == false,
              playbackRuntime.hasActivePlaybackRequest,
              let transition = appModel.presentationTransition else {
            finish(
                request,
                executionID: executionID,
                outcome: .failed(.executionCancelled)
            )
            visiblePresentation = .window
            return
        }

        let previousSurfacePresentation = visiblePresentation
        let targetSurfacePresentation = MacPlaybackPresentationHost.surfacePresentation(
            for: transition.targetPresentation
        )
        macPresentationLogger.notice(
            "transition begin from=\(transition.previousPresentation.rawValue, privacy: .public) to=\(transition.targetPresentation.rawValue, privacy: .public) hosted=\(targetSurfacePresentation.rawValue, privacy: .public)"
        )
        visiblePresentation = targetSurfacePresentation
        await Task.yield()
        guard Task.isCancelled == false else {
            finish(
                request,
                executionID: executionID,
                outcome: .failed(.executionCancelled)
            )
            return
        }

        let attached = await playbackRuntime.waitUntilPresentationSettled(
            to: targetSurfacePresentation
        )
        guard Task.isCancelled == false else {
            finish(
                request,
                executionID: executionID,
                outcome: .failed(.executionCancelled)
            )
            return
        }
        guard attached else {
            macPresentationLogger.error(
                "transition attach timed out target=\(transition.targetPresentation.rawValue, privacy: .public) hosted=\(targetSurfacePresentation.rawValue, privacy: .public)"
            )
            await restore(previousSurfacePresentation)
            finish(
                request,
                executionID: executionID,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            playbackRuntime.lastErrorMessage = "The macOS RealityView surface could not attach to PlaybackCore."
            return
        }

        let resolution = finish(
            request,
            executionID: executionID,
            outcome: .succeeded
        )
        if resolution == .presentationCommitted(transition.targetPresentation) {
            macPresentationLogger.notice(
                "transition committed presentation=\(transition.targetPresentation.rawValue, privacy: .public) hosted=\(targetSurfacePresentation.rawValue, privacy: .public) simulated=\(transition.targetPresentation == .panorama, privacy: .public) session=\(playbackRuntime.activeSessionID ?? "none", privacy: .public)"
            )
        } else {
            macPresentationLogger.error(
                "transition result ignored or rolled back target=\(transition.targetPresentation.rawValue, privacy: .public)"
            )
            await restore(previousSurfacePresentation)
        }
    }

    @discardableResult
    private func finish(
        _ request: SpatialPlatformEffectRequest,
        executionID: UUID,
        outcome: SpatialPlatformEffectOutcome,
        performsAfterTransport: Bool = true
    ) -> SpatialPlatformEffectResolution {
        let resolvedOutcome: SpatialPlatformEffectOutcome
        if let mediaSessionID = request.playbackTransportPlan?.mediaSessionID,
           playbackRuntime.activeSessionID != mediaSessionID {
            resolvedOutcome = .failed(.mediaSessionChanged)
        } else {
            resolvedOutcome = outcome
        }
        let resolution = appModel.receiveSpatialPlatformResult(
            .effectCompleted(
                SpatialPlatformEffectResult(
                    requestID: request.id,
                    executionID: executionID,
                    mediaSessionID: request.playbackTransportPlan?.mediaSessionID,
                    outcome: resolvedOutcome
                )
            )
        )
        guard performsAfterTransport else { return resolution }
        if resolvedOutcome == .failed(.mediaSessionChanged) {
            return resolution
        }
        let transportIntent: SpatialPlaybackTransportIntent?
        switch resolvedOutcome {
        case .succeeded:
            transportIntent = request.playbackTransportPlan?.afterSuccess
        case .failed:
            transportIntent = request.playbackTransportPlan?.afterFailure
        }
        if let transportIntent {
            do {
                try playbackRuntime.performSpatialPlaybackTransport(transportIntent)
            } catch {
                playbackRuntime.lastErrorMessage = error.localizedDescription
                let reason: SpatialPlaybackTransportFailureReason =
                    playbackRuntime.activeSessionID == transportIntent.mediaSessionID
                        ? .operationRejected
                        : .mediaSessionChanged
                appModel.receiveSpatialPlatformResult(
                    .playbackTransportFailed(
                        SpatialPlaybackTransportFailure(
                            requestID: request.id,
                            executionID: executionID,
                            mediaSessionID: transportIntent.mediaSessionID,
                            intent: transportIntent,
                            reason: reason
                        )
                    )
                )
            }
        }
        return resolution
    }

    @MainActor
    private func restore(_ presentation: PlaybackPresentation) async {
        macPresentationLogger.notice(
            "transition restoring presentation=\(presentation.rawValue, privacy: .public)"
        )
        visiblePresentation = presentation
        await Task.yield()
        _ = await playbackRuntime.waitUntilPresentationSettled(to: presentation)
    }
}
