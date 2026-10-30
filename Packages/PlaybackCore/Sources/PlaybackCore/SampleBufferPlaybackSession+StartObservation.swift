import CoreMedia
import Foundation

extension SampleBufferPlaybackSession {
    func beginStartObservation() {
        startObservationLock.withLock {
            startObservationInstant = ContinuousClock.now
            startMilestones = [:]
            startFirstPresentationTimes = [:]
        }
    }

    func recordStartMilestone(lane: String, presentationTime: CMTime) {
        let instant = startObservationInstant
        let elapsed = ContinuousClock.now - instant
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
        let bytes = sourceReadMeter?.totalBytesRead ?? 0
        let seconds = presentationTime.isNumeric ? presentationTime.seconds : 0
        let recorded: Bool = startObservationLock.withLock {
            guard startMilestones[lane] == nil else { return false }
            startMilestones[lane] = milliseconds
            startFirstPresentationTimes[lane] = seconds
            return true
        }
        guard recorded else { return }
        let laneName = lane
        let atMilliseconds = String(format: "%.0f", milliseconds)
        let pts = String(format: "%.3f", seconds)
        let byteCount = String(bytes)
        logger.info(
            "start.firstUnit lane=\(laneName, privacy: .public) atMs=\(atMilliseconds, privacy: .public) pts=\(pts, privacy: .public) bytes=\(byteCount, privacy: .public)"
        )
        emitStartBasisIfComplete()
    }

    private func emitStartBasisIfComplete() {
        let basis: (Double, Double)? = startObservationLock.withLock {
            guard let video = startFirstPresentationTimes["video"],
                  let audio = startFirstPresentationTimes["audio"] else { return nil }
            return (video, audio)
        }
        guard let basis else { return }
        let video = String(format: "%.3f", basis.0)
        let audio = String(format: "%.3f", basis.1)
        let delta = String(format: "%.3f", basis.1 - basis.0)
        logger.info(
            "start.basis videoPTS=\(video, privacy: .public) audioPTS=\(audio, privacy: .public) deltaSeconds=\(delta, privacy: .public)"
        )
    }
}
