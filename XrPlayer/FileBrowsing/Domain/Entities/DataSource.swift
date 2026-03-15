import Foundation

extension FileBrowsingDomain {
    public struct DataSource: Sendable, Equatable, Identifiable, Codable {
        public let id: UUID
        public let name: String
        public let sourceType: SourceType
        public let connectionInfo: ConnectionInfo

        public init(
            id: UUID = UUID(),
            name: String,
            sourceType: SourceType,
            connectionInfo: ConnectionInfo
        ) {
            self.id = id
            self.name = name
            self.sourceType = sourceType
            self.connectionInfo = connectionInfo
        }

        public var credentialSourceID: String {
            connectionInfo.credentialSourceID
        }
    }
}
