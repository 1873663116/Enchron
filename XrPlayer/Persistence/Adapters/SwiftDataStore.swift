import Foundation

public final class SwiftDataStore: ProgressStoring, ScreenPositionStoring {
    public init() {}

    public func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) async {
        _ = progress
        fatalError("TODO: implement")
    }

    public func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress? {
        _ = fileID
        fatalError("TODO: implement")
    }

    public func cleanExpiredProgress(olderThan days: Int) async {
        _ = days
        fatalError("TODO: implement")
    }

    public func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double
    ) async {
        _ = environmentID
        _ = distanceMeters
        _ = verticalOffsetMeters
        _ = angleDegrees
        fatalError("TODO: implement")
    }

    public func loadPosition(for environmentID: String) async -> PersistenceDomain.SavedScreenPosition? {
        _ = environmentID
        fatalError("TODO: implement")
    }
}
