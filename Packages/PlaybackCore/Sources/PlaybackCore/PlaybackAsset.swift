@preconcurrency import AVFoundation

public struct PlaybackAsset: @unchecked Sendable {
    nonisolated(unsafe) let value: AVAsset

    public nonisolated init(_ value: AVAsset) {
        self.value = value
    }
}
