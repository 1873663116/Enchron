import Foundation
import Observation

@Observable
public final class PlaybackSession {
    public let id: UUID
    public var mediaFile: PlaybackModel.MediaFile?
    public var state: PlaybackModel.PlaybackState
    public var speed: PlaybackModel.PlaybackSpeed
    public var position: PlaybackModel.PlaybackPosition
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        mediaFile: PlaybackModel.MediaFile? = nil,
        state: PlaybackModel.PlaybackState = .idle,
        speed: PlaybackModel.PlaybackSpeed = .default,
        position: PlaybackModel.PlaybackPosition = .init(seconds: 0, duration: 0),
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
