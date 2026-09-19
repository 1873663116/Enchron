@preconcurrency import AVFoundation
import Foundation

/// Recovery from a video decoder the system has flushed.
///
/// A flushed renderer refuses to decode again until its stream is restarted, so
/// the session stops feeding it and waits for the reader to finish. The reopen
/// that follows then starts from a quiet provider rather than racing a reader
/// still draining the old decoder's backlog.
extension SampleBufferPlaybackSession {
    /// Single flight: the foreground return and the play path can both ask for
    /// this, and whichever asks second waits on the same stop instead of
    /// starting another one.
    func prepareForRendererRecovery() async throws {
        if let inFlight = rendererRecoveryLock.withLock({ rendererRecoveryTask }) {
            try await inFlight.value
            return
        }
        let task = Task { [self] in
            try await stopDeliveryForRendererRecovery()
        }
        let alreadyRunning = rendererRecoveryLock.withLock { () -> Task<Void, Error>? in
            if let existing = rendererRecoveryTask { return existing }
            rendererRecoveryTask = task
            return nil
        }
        if let alreadyRunning {
            try await alreadyRunning.value
            return
        }
        defer { rendererRecoveryLock.withLock { rendererRecoveryTask = nil } }
        try await task.value
    }

    private func stopDeliveryForRendererRecovery() async throws {
        guard !isClosed, !isResetting, needsVideoRendererRecovery else { return }
        _ = beginRendererFlushRecovery()
        let stoppedDelivery = stopVideoDelivery(caller: "rendererFlushRecovery")
        await stoppedDelivery?.value
        try Task.checkCancellation()
    }

    /// The renderer's own view of itself around a recovery. The enqueue results
    /// say the samples were taken; only these say whether it intends to render
    /// them.
    func emitRendererRecoveryState(_ stage: String) {
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "videoRenderer.recoveryState",
            outcome: .succeeded,
            details: [
                "stage": stage,
                "requiresFlush": String(renderer.requiresFlushToResumeDecoding),
                "status": currentVideoRendererStatus,
                "error": currentVideoRendererError ?? "none",
                "hasDisplayedImage": String(renderer.displayedPixelBuffer() != nil),
                "rate": String(synchronizer.rate),
                "timeSeconds": String(format: "%.3f", synchronizer.currentTime().seconds)
            ]
        )
    }
}
