import CoreMedia
import Foundation

extension SampleBufferPlaybackSession {
    @discardableResult
    func openAudioAttachment(
        url: URL,
        asset: PlaybackAsset?,
        seconds: Double,
        streamIndex: Int?,
        reason: String
    ) async throws -> AudioSampleProviderInfo? {
        let startTime = CMTime(seconds: seconds, preferredTimescale: 60_000)
        let queuedBefore = streamIndex.map { demuxSession?.queuedPacketCount(streamIndex: $0) ?? -1 } ?? -1
        let headBefore = streamIndex.flatMap { index in
            demuxSession.map { String(format: "%.3f", $0.queueHeadSeconds(streamIndex: index)) }
        } ?? "none"
        let epochBefore = demuxSession?.currentEpoch()
        try await audioProvider.prepare(
            url: url,
            asset: asset,
            startTime: startTime,
            streamIndex: streamIndex
        )
        let epochAfter = demuxSession?.currentEpoch()
        if let epochBefore, let epochAfter, epochBefore != epochAfter {
            throw AudioSampleProviderError.read(
                "source epoch moved from \(epochBefore) to \(epochAfter) while opening the audio attachment"
            )
        }
        guard let info = audioProvider.info else { return nil }
        let epochLabel = epochAfter.map(String.init) ?? "none"
        let queuedAfter = demuxSession?.queuedPacketCount(streamIndex: info.streamIndex) ?? -1
        let summary = "audio.attach.open reason=\(reason) index=\(info.streamIndex)"
            + " codec=\(info.codecName) epoch=\(epochLabel)"
            + " queuedBefore=\(queuedBefore) queuedAfter=\(queuedAfter) headBefore=\(headBefore)"
        logger.info("\(summary, privacy: .public)")
        return info
    }
}
