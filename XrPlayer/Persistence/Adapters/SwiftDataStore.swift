import Foundation

public final class SwiftDataStore: ProgressStoring, ScreenPositionStoring {
    private let storage: Storage

    public init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        self.storage = Storage(storageURL: resolvedURL)
    }

    public func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) async {
        await storage.saveProgress(progress)
    }

    public func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress? {
        await storage.loadProgress(for: fileID)
    }

    public func cleanExpiredProgress(olderThan days: Int) async {
        await storage.cleanExpiredProgress(olderThan: days)
    }

    public func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double
    ) async {
        await storage.savePosition(
            for: environmentID,
            distanceMeters: distanceMeters,
            verticalOffsetMeters: verticalOffsetMeters,
            angleDegrees: angleDegrees
        )
    }

    public func loadPosition(for environmentID: String) async -> PersistenceDomain.SavedScreenPosition? {
        await storage.loadPosition(for: environmentID)
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport
            .appendingPathComponent("XrPlayer", isDirectory: true)
            .appendingPathComponent("persistence-store.json", isDirectory: false)
    }
}

private actor Storage {
    private struct StoredProgress: Codable {
        let seconds: Double
        let updatedAt: Date
    }

    private struct StoredScreenPosition: Codable {
        let distanceMeters: Double
        let verticalOffsetMeters: Double
        let viewAngleDegrees: Double
    }

    private struct StateSnapshot: Codable {
        var progressByFileID: [String: StoredProgress]
        var screenPositionByEnvironmentID: [String: StoredScreenPosition]

        static let empty = StateSnapshot(progressByFileID: [:], screenPositionByEnvironmentID: [:])
    }

    private let storageURL: URL
    private var snapshot: StateSnapshot
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(storageURL: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.storageURL = storageURL
        self.encoder = encoder
        self.decoder = decoder
        self.snapshot = Self.loadSnapshot(from: storageURL, decoder: decoder)
    }

    func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) {
        snapshot.progressByFileID[progress.fileID.rawValue] = StoredProgress(
            seconds: progress.position.seconds,
            updatedAt: progress.updatedAt
        )
        persistSnapshot()
    }

    func loadProgress(for fileID: PersistenceDomain.FileIdentifier) -> PersistenceDomain.PlaybackProgress? {
        guard let stored = snapshot.progressByFileID[fileID.rawValue] else {
            return nil
        }
        return PersistenceDomain.PlaybackProgress(
            fileID: fileID,
            position: .init(seconds: stored.seconds),
            updatedAt: stored.updatedAt
        )
    }

    func cleanExpiredProgress(olderThan days: Int) {
        if days <= 0 {
            snapshot.progressByFileID.removeAll()
            persistSnapshot()
            return
        }

        let expirationDate = Date().addingTimeInterval(-Double(days) * 86_400)
        snapshot.progressByFileID = snapshot.progressByFileID.filter { _, progress in
            progress.updatedAt >= expirationDate
        }
        persistSnapshot()
    }

    func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double
    ) {
        let key = environmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else { return }

        snapshot.screenPositionByEnvironmentID[key] = StoredScreenPosition(
            distanceMeters: distanceMeters,
            verticalOffsetMeters: verticalOffsetMeters,
            viewAngleDegrees: angleDegrees
        )
        persistSnapshot()
    }

    func loadPosition(for environmentID: String) -> PersistenceDomain.SavedScreenPosition? {
        let key = environmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false,
              let position = snapshot.screenPositionByEnvironmentID[key]
        else {
            return nil
        }

        return PersistenceDomain.SavedScreenPosition(
            environmentID: key,
            distanceMeters: position.distanceMeters,
            verticalOffsetMeters: position.verticalOffsetMeters,
            viewAngleDegrees: position.viewAngleDegrees
        )
    }

    private static func loadSnapshot(
        from storageURL: URL,
        decoder: JSONDecoder
    ) -> StateSnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode(StateSnapshot.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    private func persistSnapshot() {
        do {
            let directoryURL = storageURL.deletingLastPathComponent()
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[SwiftDataStore] failed to persist snapshot: \(error.localizedDescription)")
        }
    }
}
