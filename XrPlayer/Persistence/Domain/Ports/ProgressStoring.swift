import Foundation

public protocol ProgressStoring {
    func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) async
    func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress?
    func loadRecentlyPlayed(limit: Int) async -> [PersistenceDomain.PlaybackProgress]
    func cleanExpiredProgress(olderThan days: Int) async
}

extension ProgressStoring {
    public func loadRecentlyPlayed(limit: Int) async -> [PersistenceDomain.PlaybackProgress] { [] }
}
