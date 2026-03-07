import Foundation

extension FileBrowsingDomain {
    public struct MediaFolder: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let dataSourceID: UUID
        public let path: String
        public let url: URL

        public init(id: UUID = UUID(), name: String, dataSourceID: UUID, path: String, url: URL) {
            self.id = id
            self.name = name
            self.dataSourceID = dataSourceID
            self.path = path
            self.url = url
        }
    }
}
