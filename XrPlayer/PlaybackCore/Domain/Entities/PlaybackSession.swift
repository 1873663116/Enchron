import Foundation
import Observation

@Observable
public final class PlaybackSession {
    public let id: UUID
    public var mediaFile: PlaybackCoreDomain.MediaFile?
    public var state: PlaybackCoreDomain.PlaybackState
    public var speed: PlaybackCoreDomain.PlaybackSpeed
    public var position: PlaybackCoreDomain.PlaybackPosition
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        mediaFile: PlaybackCoreDomain.MediaFile? = nil,
        state: PlaybackCoreDomain.PlaybackState = .idle,
        speed: PlaybackCoreDomain.PlaybackSpeed = .default,
        position: PlaybackCoreDomain.PlaybackPosition = .init(seconds: 0, duration: 0),
        startedAt: Date = Date()
    ) {
        self.id = id
        self.mediaFile = mediaFile
        self.state = state
        self.speed = speed
        self.position = position
        self.startedAt = startedAt
    }
}
