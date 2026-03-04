import Foundation

extension FileBrowsingDomain {
    public struct FileFilter: Sendable, Equatable {
        public let allowedExtensions: Set<String>

        public init(allowedExtensions: Set<String>) {
            self.allowedExtensions = Set(allowedExtensions.map { $0.lowercased() })
        }

        public func matches(fileURL: URL) -> Bool {
            allowedExtensions.contains(fileURL.pathExtension.lowercased())
        }

        public static let playable = FileFilter(
            allowedExtensions: [
                "mp4", "mkv", "avi", "mov", "m4v", "webm", "ts", "m2ts", "flv"
            ]
        )
    }
}
