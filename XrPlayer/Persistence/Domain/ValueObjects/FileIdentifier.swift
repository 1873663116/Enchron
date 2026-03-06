import Foundation

public enum PersistenceDomain {}

extension PersistenceDomain {
    public struct FileIdentifier: Sendable, Equatable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func make(path: String, sizeInBytes: Int64, serverFingerprint: String?) -> FileIdentifier {
            let fingerprint = normalizedFingerprint(serverFingerprint) ?? "local"
            let normalizedSize = max(0, sizeInBytes)
            return FileIdentifier(
                rawValue: "\(normalizedPath(path))|\(normalizedSize)|\(fingerprint)"
            )
        }

        public static func make(url: URL, sizeInBytes: Int64, serverFingerprint: String? = nil) -> FileIdentifier {
            let fingerprint =
                normalizedFingerprint(serverFingerprint)
                ?? (url.isFileURL ? "local" : (url.scheme?.lowercased() ?? "remote"))
            let normalizedSize = max(0, sizeInBytes)
            let path: String
            if url.isFileURL {
                path = url.standardizedFileURL.path
            } else {
                path = url.path.removingPercentEncoding ?? url.path
            }

            return FileIdentifier(
                rawValue: "\(normalizedPath(path))|\(normalizedSize)|\(fingerprint)"
            )
        }

        private static func normalizedFingerprint(_ fingerprint: String?) -> String? {
            guard let fingerprint else { return nil }
            let trimmed = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return trimmed.lowercased()
        }

        private static func normalizedPath(_ path: String) -> String {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return "/" }

            let hadLeadingSlash = trimmed.hasPrefix("/")
            let components = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            guard components.isEmpty == false else { return "/" }

            let normalized = components.joined(separator: "/")
            if hadLeadingSlash {
                return "/" + normalized
            }
            return normalized
        }
    }
}
