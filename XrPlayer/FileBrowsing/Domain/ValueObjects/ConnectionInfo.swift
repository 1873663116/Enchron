import Foundation

extension FileBrowsingDomain {
    public struct ConnectionInfo: Sendable, Equatable, Codable {
        public let sourceType: SourceType
        public let host: String?
        public let port: Int?
        public let username: String?
        public let rootPath: String

        public init(
            sourceType: SourceType,
            host: String? = nil,
            port: Int? = nil,
            username: String? = nil,
            rootPath: String = "/"
        ) {
            self.sourceType = sourceType
            self.host = host
            self.port = port
            self.username = username
            self.rootPath = rootPath
        }
    }

    public enum ConnectionStatus: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }
}
