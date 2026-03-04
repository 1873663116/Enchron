import Foundation

extension FileBrowsingDomain {
    public struct MediaFile: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let sizeInBytes: Int64
        public let modifiedAt: Date
        public let fileExtension: String
        public let url: URL

        public init(
            id: UUID = UUID(),
            name: String,
            sizeInBytes: Int64,
            modifiedAt: Date,
            fileExtension: String,
            url: URL
        ) {
            self.id = id
            self.name = name
            self.sizeInBytes = sizeInBytes
            self.modifiedAt = modifiedAt
            self.fileExtension = fileExtension.lowercased()
            self.url = url
        }
    }
}
