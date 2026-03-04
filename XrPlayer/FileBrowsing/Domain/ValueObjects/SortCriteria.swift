import Foundation

extension FileBrowsingDomain {
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

        public static let nameAscending = SortCriteria(key: .name, order: .ascending)
    }
}
