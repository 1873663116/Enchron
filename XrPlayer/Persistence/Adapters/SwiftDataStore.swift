import Foundation

/// Minimal viable implementation of progress and screen position storage.
///
/// Uses JSON-encoded UserDefaults storage as a starting point.
/// Can be migrated to SwiftData when the persistence layer matures.
public nonisolated final class SwiftDataStore: ProgressStoring, ScreenPositionStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let progressPrefix = "xrplayer.progress."
    private static let screenPositionPrefix = "xrplayer.screenPos."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - ProgressStoring

    public func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) async {
        let key = Self.progressPrefix + progress.fileID.rawValue
        let entry = ProgressEntry(
            seconds: progress.position.seconds,
            updatedAt: progress.updatedAt.timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: key)
        }
    }

    public func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress? {
        let key = Self.progressPrefix + fileID.rawValue
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(ProgressEntry.self, from: data) else {
            return nil
        }
        return PersistenceDomain.PlaybackProgress(
            fileID: fileID,
            position: PersistenceDomain.ProgressPosition(seconds: entry.seconds),
            updatedAt: Date(timeIntervalSince1970: entry.updatedAt)
        )
    }

    public func cleanExpiredProgress(olderThan days: Int) async {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970
        let allKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(Self.progressPrefix)
        }
        for key in allKeys {
            guard let data = defaults.data(forKey: key),
                  let entry = try? JSONDecoder().decode(ProgressEntry.self, from: data) else {
                continue
            }
            if entry.updatedAt < cutoff {
                defaults.removeObject(forKey: key)
            }
        }
    }

    public func loadRecentlyPlayed(limit: Int) async -> [PersistenceDomain.PlaybackProgress] {
        guard limit > 0 else { return [] }
        let allKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(Self.progressPrefix)
        }
        var entries: [PersistenceDomain.PlaybackProgress] = []
        for key in allKeys {
            guard let data = defaults.data(forKey: key),
                  let entry = try? JSONDecoder().decode(ProgressEntry.self, from: data) else {
                continue
            }
            let rawValue = String(key.dropFirst(Self.progressPrefix.count))
            let fileID = PersistenceDomain.FileIdentifier(rawValue: rawValue)
            entries.append(PersistenceDomain.PlaybackProgress(
                fileID: fileID,
                position: PersistenceDomain.ProgressPosition(seconds: entry.seconds),
                updatedAt: Date(timeIntervalSince1970: entry.updatedAt)
            ))
        }
        // Sort by most recent first, dedup by FileIdentifier (keep newest)
        entries.sort { $0.updatedAt > $1.updatedAt }
        var seen = Set<PersistenceDomain.FileIdentifier>()
        var result: [PersistenceDomain.PlaybackProgress] = []
        for entry in entries {
            guard seen.insert(entry.fileID).inserted else { continue }
            result.append(entry)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - ScreenPositionStoring

    public func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double
    ) async {
        let key = Self.screenPositionPrefix + environmentID
        let entry = ScreenPositionEntry(
            distanceMeters: distanceMeters,
            verticalOffsetMeters: verticalOffsetMeters,
            angleDegrees: angleDegrees
        )
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: key)
        }
    }

    public func loadPosition(for environmentID: String) async -> PersistenceDomain.SavedScreenPosition? {
        let key = Self.screenPositionPrefix + environmentID
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(ScreenPositionEntry.self, from: data) else {
            return nil
        }
        return PersistenceDomain.SavedScreenPosition(
            environmentID: environmentID,
            distanceMeters: entry.distanceMeters,
            verticalOffsetMeters: entry.verticalOffsetMeters,
            viewAngleDegrees: entry.angleDegrees
        )
    }
}

// MARK: - Internal Codable types

private nonisolated struct ProgressEntry: Codable, Sendable {
    let seconds: Double
    let updatedAt: Double
}

private nonisolated struct ScreenPositionEntry: Codable, Sendable {
    let distanceMeters: Double
    let verticalOffsetMeters: Double
    let angleDegrees: Double
}
