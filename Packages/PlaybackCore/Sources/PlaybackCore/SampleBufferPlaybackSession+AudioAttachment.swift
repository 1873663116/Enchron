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
        logger.info(
            "audio.attach.open reason=\(reason, privacy: .public) index=\(info.streamIndex, privacy: .public) codec=\(info.codecName, privacy: .public) epoch=\(epochLabel, privacy: .public)"
        )
        return info
    }
}
