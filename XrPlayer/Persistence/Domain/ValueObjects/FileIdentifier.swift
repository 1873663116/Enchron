import Foundation

public enum PersistenceDomain {}

extension PersistenceDomain {
    public struct FileIdentifier: Sendable, Equatable, Hashable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static func make(path: String, sizeInBytes: Int64, serverFingerprint: String?) -> FileIdentifier {
            let fingerprint = serverFingerprint ?? "local"
            return FileIdentifier(rawValue: "\(path)|\(sizeInBytes)|\(fingerprint)")
        }
    }
}
