import Foundation


public nonisolated enum FileBrowsingDomain {}

nonisolated extension FileBrowsingDomain {
    public enum SourceType: String, Sendable, CaseIterable, Codable {
        case local
        case photoLibrary
        case smb
        case webDAV
    }
}


nonisolated extension FileBrowsingDomain {
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

        /// Creates a remote connection info.
        ///
        /// For SMB, `address` identifies one server by host name or IP address.
        ///
        /// For WebDAV: `address` is a full URL or host:port/path.
        public static func remote(
            sourceType: SourceType,
            address: String,
            username: String? = nil
        ) throws -> ConnectionInfo {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw ConnectionInfoError.emptyAddress
            }

            if sourceType == .smb {
                let preparedAddress = canonicalAddress(for: sourceType, rawAddress: trimmed)
                guard let components = URLComponents(string: preparedAddress),
                      let host = components.host,
                      host.isEmpty == false,
                      normalizedPath(components.path) == "/" else {
                    throw ConnectionInfoError.invalidSMBAddress
                }
                return ConnectionInfo(
                    sourceType: sourceType,
                    address: trimmed,
                    scheme: "smb",
                    host: host,
                    port: components.port,
                    username: username,
                    rootPath: "/"
                )
            }

            // WebDAV: parse as URL
            let preparedAddress = canonicalAddress(for: sourceType, rawAddress: trimmed)
            guard let components = URLComponents(string: preparedAddress),
                  let host = components.host,
                  host.isEmpty == false else {
                throw ConnectionInfoError.invalidAddress
            }

            let path = normalizedPath(components.path)
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

        public var credentialSourceID: String {
            "\(legacyCredentialSourceID):\(accountNamespace)"
        }

        var legacyCredentialSourceID: String {
            let type = sourceType.rawValue
            let host = host ?? ""
            let port = port ?? 0

            if sourceType == .smb {
                return "\(type):\(host):\(port)"
            }

            return "\(type):\(host):\(port):\(rootPath)"
        }

        public var mediaIdentitySourceKey: String {
            let normalizedHost = (host ?? "").lowercased()
            let normalizedScheme = (scheme ?? "").lowercased()
            let normalizedPort = port ?? Self.defaultPort(for: normalizedScheme)
            return [
                sourceType.rawValue,
                normalizedScheme,
                normalizedHost,
                String(normalizedPort),
                accountNamespace,
            ]
                .joined(separator: ":")
        }

        private var accountNamespace: String {
            let value = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "guest" : value
        }

        private static func defaultPort(for scheme: String) -> Int {
            switch scheme {
            case "http": 80
            case "https": 443
            case "smb": 445
            default: 0
            }
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
        case invalidSMBAddress

        public var errorDescription: String? {
            switch self {
            case .emptyAddress:
                return "Server address is required."
            case .invalidAddress:
                return "Invalid server address."
            case .invalidSMBAddress:
                return "SMB address must be an IP address (e.g., 192.168.1.20). Do not include smb://, paths, or share names."
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


nonisolated extension FileBrowsingDomain {
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
