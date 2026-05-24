import Foundation

public nonisolated final class SavedDataSourceStore: SavedDataSourceRecordStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "xrplayer.savedDataSources"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadSavedDataSourceRecords() -> Data? {
        defaults.data(forKey: key)
    }

    public func saveSavedDataSourceRecords(_ data: Data?) {
        defaults.set(data, forKey: key)
    }
}
