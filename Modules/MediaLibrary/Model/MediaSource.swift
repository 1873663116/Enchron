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
        /// For SMB: `address` must be an IP address (digits and dots only).
        /// The connection is host-only — no share name required at this stage.
        /// Share selection happens after successful login via the SMB adapter.
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
                // SMB: address must be IP-only (digits and dots).
                guard Self.isValidIPAddress(trimmed) else {
                    throw ConnectionInfoError.invalidSMBAddress
                }
                return ConnectionInfo(
                    sourceType: sourceType,
                    address: trimmed,
                    scheme: "smb",
                    host: trimmed,
                    port: nil,
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

        /// Creates an SMB connection info with a specific share selected.
        /// Used after the user picks a share from the share list.
        public func withSMBShare(_ shareName: String) -> ConnectionInfo {
            ConnectionInfo(
                sourceType: sourceType,
                address: address,
                scheme: scheme,
                host: host,
                port: port,
                username: username,
                rootPath: "/\(shareName)"
            )
        }

        public var credentialSourceID: String {
            let type = sourceType.rawValue
            let host = host ?? ""
            let port = port ?? 0

            if sourceType == .smb {
                return "\(type):\(host):\(port)"
            }

            return "\(type):\(host):\(port):\(rootPath)"
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

        /// Validates that a string is a valid IPv4 address (digits and dots only).
        private static func isValidIPAddress(_ string: String) -> Bool {
            let allowedCharacters = CharacterSet(charactersIn: "0123456789.")
            guard string.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
                return false
            }
            let parts = string.split(separator: ".")
            guard parts.count == 4 else { return false }
            return parts.allSatisfy { part in
                guard let num = Int(part), num >= 0, num <= 255 else { return false }
                return true
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

