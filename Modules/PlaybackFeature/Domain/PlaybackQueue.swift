import Foundation

public struct PlaybackQueueEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let isCurrent: Bool

    public init(id: UUID, displayName: String, isCurrent: Bool) {
        self.id = id
        self.displayName = displayName
        self.isCurrent = isCurrent
    }
}

public struct PlaybackQueueSnapshot: Equatable, Sendable {
    public let entries: [PlaybackQueueEntry]

    public init(entries: [PlaybackQueueEntry] = []) {
        self.entries = entries
    }

    public static let empty = PlaybackQueueSnapshot()
}
