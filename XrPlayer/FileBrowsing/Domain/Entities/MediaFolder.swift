import Foundation

extension FileBrowsingDomain {
    public struct MediaFolder: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let dataSourceID: UUID
        public let path: String
        public let url: URL

        public init(id: String? = nil, name: String, dataSourceID: UUID, path: String, url: URL) {
            self.id = id ?? Self.identity(for: dataSourceID, path: path)
            self.name = name
            self.dataSourceID = dataSourceID
            self.path = path
            self.url = url
        }

        private static func identity(for dataSourceID: UUID, path: String) -> String {
            let normalizedPath = path.isEmpty ? "/" : path
            return "\(dataSourceID.uuidString.lowercased()):\(normalizedPath)"
        }
    }
}
