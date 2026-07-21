import Foundation


public nonisolated struct PlaybackFileIdentifier: Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make(path: String, sizeInBytes: Int64, serverFingerprint: String?) -> PlaybackFileIdentifier {
        let fingerprint = serverFingerprint ?? "local"
        return PlaybackFileIdentifier(rawValue: "\(path)|\(sizeInBytes)|\(fingerprint)")
    }
}

public nonisolated struct ProgressPosition: Sendable, Equatable {
    public let seconds: Double

    public init(seconds: Double) {
        self.seconds = max(0, seconds)
    }
}

public nonisolated struct PlaybackProgress: Sendable, Equatable {
    public let fileID: PlaybackFileIdentifier
    public let position: ProgressPosition
    public let updatedAt: Date

    public init(fileID: PlaybackFileIdentifier, position: ProgressPosition, updatedAt: Date = Date()) {
        self.fileID = fileID
        self.position = position
        self.updatedAt = updatedAt
    }
}


public nonisolated protocol ProgressStoring: Sendable {
    func saveProgress(_ progress: PlaybackProgress) async
    func loadProgress(for fileID: PlaybackFileIdentifier) async -> PlaybackProgress?
    func loadRecentlyPlayed(limit: Int) async -> [PlaybackProgress]
    func cleanExpiredProgress(olderThan days: Int) async
    func clearAllProgress() async
}

nonisolated extension ProgressStoring {
    public func loadRecentlyPlayed(limit: Int) async -> [PlaybackProgress] { [] }
    public func clearAllProgress() async {}
}


public nonisolated final class PlaybackProgressStore: ProgressStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let keyPrefix = "xrplayer.progress."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func saveProgress(_ progress: PlaybackProgress) async {
        let entry = Entry(
            seconds: progress.position.seconds,
            updatedAt: progress.updatedAt.timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: Self.keyPrefix + progress.fileID.rawValue)
        }
    }

    public func loadProgress(
        for fileID: PlaybackFileIdentifier
    ) async -> PlaybackProgress? {
        guard let data = defaults.data(forKey: Self.keyPrefix + fileID.rawValue),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return .init(
            fileID: fileID,
            position: .init(seconds: entry.seconds),
            updatedAt: Date(timeIntervalSince1970: entry.updatedAt)
        )
    }

    public func cleanExpiredProgress(olderThan days: Int) async {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        for key in progressKeys {
            guard let data = defaults.data(forKey: key),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data),
                  entry.updatedAt < cutoff else { continue }
            defaults.removeObject(forKey: key)
        }
    }

    public func clearAllProgress() async {
        progressKeys.forEach(defaults.removeObject(forKey:))
    }

    public func loadRecentlyPlayed(limit: Int) async -> [PlaybackProgress] {
        guard limit > 0 else { return [] }
        let entries = progressKeys.compactMap { key -> PlaybackProgress? in
            guard let data = defaults.data(forKey: key),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
                return nil
            }
            let fileID = PlaybackFileIdentifier(
                rawValue: String(key.dropFirst(Self.keyPrefix.count))
            )
            return .init(
                fileID: fileID,
                position: .init(seconds: entry.seconds),
                updatedAt: Date(timeIntervalSince1970: entry.updatedAt)
            )
        }.sorted { $0.updatedAt > $1.updatedAt }

        var seen = Set<PlaybackFileIdentifier>()
        return entries.filter { seen.insert($0.fileID).inserted }.prefix(limit).map { $0 }
    }

    private var progressKeys: [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Self.keyPrefix) }
    }

    private struct Entry: Codable, Sendable {
        let seconds: Double
        let updatedAt: Double
    }
}
