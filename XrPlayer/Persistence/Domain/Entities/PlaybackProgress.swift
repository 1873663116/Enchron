import Foundation

nonisolated extension PersistenceDomain {
    public struct PlaybackProgress: Sendable, Equatable {
        public let fileID: FileIdentifier
        public let position: ProgressPosition
        public let updatedAt: Date

        public init(fileID: FileIdentifier, position: ProgressPosition, updatedAt: Date = Date()) {
            self.fileID = fileID
            self.position = position
            self.updatedAt = updatedAt
        }
    }
}
