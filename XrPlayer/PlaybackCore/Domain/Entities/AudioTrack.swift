import Foundation

extension PlaybackCoreDomain {
    public struct AudioTrack: Sendable, Equatable, Identifiable {
        public let id: String
        public let languageCode: String?
        public let displayName: String
        public let isDefault: Bool

        public init(id: String, languageCode: String?, displayName: String, isDefault: Bool = false) {
            self.id = id
            self.languageCode = languageCode
            self.displayName = displayName
            self.isDefault = isDefault
        }
    }
}
