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

        public var credentialStorageKey: String? {
            guard let normalizedHost, sourceType.supportsRemoteCredentialStorage else {
                return nil
            }

            let resolvedPort = port ?? sourceType.defaultRemotePort
            return "\(sourceType.rawValue):\(normalizedHost):\(resolvedPort):\(normalizedRootPath)"
        }

        private var normalizedHost: String? {
            guard let host else { return nil }
            let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return trimmed.lowercased()
        }

        private var normalizedRootPath: String {
            let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return "/" }
            return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        }
    }

    public enum ConnectionStatus: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }
}

private extension FileBrowsingDomain.SourceType {
    var supportsRemoteCredentialStorage: Bool {
        switch self {
        case .webDAV, .smb:
            return true
        case .local, .photoLibrary:
            return false
        }
    }

    var defaultRemotePort: Int {
        switch self {
        case .smb:
            return 445
        case .webDAV:
            return 443
        case .local, .photoLibrary:
            return 0
        }
    }
}
