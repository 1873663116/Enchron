import Foundation

nonisolated protocol MediaLibraryStoring: Sendable {
    func load() throws -> FileBrowsingDomain.MediaLibrary
    func save(_ library: FileBrowsingDomain.MediaLibrary) throws
}

nonisolated final class UserDefaultsMediaLibraryStore: MediaLibraryStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "enchron.mediaLibrary") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> FileBrowsingDomain.MediaLibrary {
        guard let data = defaults.data(forKey: key) else {
            return FileBrowsingDomain.MediaLibrary()
        }
        return try decoder.decode(FileBrowsingDomain.MediaLibrary.self, from: data)
    }

    public func save(_ library: FileBrowsingDomain.MediaLibrary) throws {
        defaults.set(try encoder.encode(library), forKey: key)
    }
}
