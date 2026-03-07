import Foundation

extension FileBrowsingDomain {
    public struct ConnectionInfo: Sendable, Equatable, Codable {
        public let sourceType: SourceType
        public let address: String?
        public let scheme: String?
        public let host: String?
        public let port: Int?
        public let username: String?
        public let rootPath: String

        public init(
            sourceType: SourceType,
            address: String? = nil,
            scheme: String? = nil,
            host: String? = nil,
            port: Int? = nil,
            username: String? = nil,
            rootPath: String = "/"
        ) {
            self.sourceType = sourceType
            self.address = address?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.scheme = scheme?.lowercased()
            self.host = host
            self.port = port
            self.username = username
            self.rootPath = Self.normalizedPath(rootPath)
        }

        public static func remote(
            sourceType: SourceType,
            address: String,
            username: String? = nil
        ) throws -> ConnectionInfo {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw ConnectionInfoError.emptyAddress
            }

            let preparedAddress = canonicalAddress(for: sourceType, rawAddress: trimmed)
            guard let components = URLComponents(string: preparedAddress),
                  let host = components.host,
                  host.isEmpty == false else {
                throw ConnectionInfoError.invalidAddress
            }

            let path = normalizedPath(components.path)
            if sourceType == .smb && shareName(from: path) == nil {
                throw ConnectionInfoError.missingSMBShare
            }

            return ConnectionInfo(
                sourceType: sourceType,
                address: trimmed,
                scheme: components.scheme,
                host: host,
                port: components.port,
                username: username,
                rootPath: path
            )
        }

        public var displayAddress: String {
            if let address, address.isEmpty == false {
                return address
            }

            switch sourceType {
            case .local, .photoLibrary:
                return rootPath
            case .webDAV, .smb:
                var value = ""
                if let scheme, scheme.isEmpty == false {
                    value += "\(scheme)://"
                }
                value += host ?? ""
                if let port {
                    value += ":\(port)"
                }
                if rootPath != "/" {
                    value += rootPath
                }
                return value
            }
        }

        private static func canonicalAddress(for sourceType: SourceType, rawAddress: String) -> String {
            if rawAddress.contains("://") {
                return rawAddress
            }

            switch sourceType {
            case .smb:
                return "smb://\(rawAddress)"
            case .webDAV:
                return "http://\(rawAddress)"
            case .local, .photoLibrary:
                return rawAddress
            }
        }

        private static func shareName(from path: String) -> String? {
            path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init)
        }

        private static func normalizedPath(_ path: String) -> String {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return "/" }
            if trimmed.hasPrefix("/") {
                return trimmed
            }
            return "/" + trimmed
        }
    }

    public enum ConnectionInfoError: LocalizedError {
        case emptyAddress
        case invalidAddress
        case missingSMBShare

        public var errorDescription: String? {
            switch self {
            case .emptyAddress:
                return "Server address is required."
            case .invalidAddress:
                return "Invalid server address."
            case .missingSMBShare:
                return "SMB address must include a share name, for example smb://192.168.1.20/share."
            }
        }
    }

    public enum ConnectionStatus: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }
}
