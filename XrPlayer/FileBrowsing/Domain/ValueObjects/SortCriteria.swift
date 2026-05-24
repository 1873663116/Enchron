import Foundation

nonisolated extension FileBrowsingDomain {
    public struct SortCriteria: Sendable, Equatable {
        public enum Key: Sendable {
            case name
            case modifiedDate
            case size
        }

        public enum Order: Sendable {
            case ascending
            case descending
        }

        public let key: Key
        public let order: Order

        public init(key: Key, order: Order) {
            self.key = key
            self.order = order
        }

        public func sorted(_ files: [FileBrowsingDomain.MediaFile]) -> [FileBrowsingDomain.MediaFile] {
            let sorted: [FileBrowsingDomain.MediaFile]

            switch key {
            case .name:
                sorted = files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .modifiedDate:
                sorted = files.sorted { $0.modifiedAt < $1.modifiedAt }
            case .size:
                sorted = files.sorted { $0.sizeInBytes < $1.sizeInBytes }
            }

            switch order {
            case .ascending:
                return sorted
            case .descending:
                return Array(sorted.reversed())
            }
        }

        public static let nameAscending = SortCriteria(key: .name, order: .ascending)
    }
}
