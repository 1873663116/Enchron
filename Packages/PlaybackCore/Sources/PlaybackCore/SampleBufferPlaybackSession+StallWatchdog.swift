import Foundation

extension SampleBufferPlaybackSession {
    func noteSourceBytesForWatchdog() {
        let bytes = sourceReadMeter?.totalBytesRead ?? 0
        sourceProgressLock.withLock {
            if bytes != sourceProgressBytes {
                sourceProgressBytes = bytes
                sourceProgressInstant = ContinuousClock.now
            }
        }
    }

    func noteAcceptedVideoSampleForWatchdog() {
        sourceProgressLock.withLock {
            lastAcceptedVideoSampleInstant = ContinuousClock.now
        }
    }

    func startSourceProgressWatchdog() {
        sourceProgressLock.withLock {
            guard sourceProgressWatchdog == nil else { return }
            sourceProgressInstant = ContinuousClock.now
            lastAcceptedVideoSampleInstant = ContinuousClock.now
            sourceProgressBytes = sourceReadMeter?.totalBytesRead ?? 0
            sourceProgressWatchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self else { return }
                    if self.isClosed { return }
                    self.evaluateSourceProgress()
                }
            }
        }
    }

    func stopSourceProgressWatchdog() {
        let task = sourceProgressLock.withLock { () -> Task<Void, Never>? in
            let task = sourceProgressWatchdog
            sourceProgressWatchdog = nil
            return task
        }
        task?.cancel()
    }

    private func evaluateSourceProgress() {
        noteSourceBytesForWatchdog()
        let (bytesInstant, sampleInstant, bytes) = sourceProgressLock.withLock {
            (sourceProgressInstant, lastAcceptedVideoSampleInstant, sourceProgressBytes)
        }
        let now = ContinuousClock.now
        let newest = max(bytesInstant, sampleInstant)
        let limit = PlaybackBufferingPolicy.effectiveStallLimit
        let stalled = now - newest >= limit
        let stateNow = readinessLock.withLock { readinessState }
        if stalled, stateNow == .playable, hasStartedTimeline, timelineStartRate > 0 {
            updateReadiness(.stalled, reason: "playbackStall bytes=\(bytes)")
        } else if !stalled, stateNow == .stalled {
            updateReadiness(.playable, reason: "sourceResumed")
        }
    }
}
