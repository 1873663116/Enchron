import Foundation

public struct StreamingPlaybackInformation: Equatable, Sendable {
    public struct Detail: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var value: String

        public init(id: String, title: String, value: String) {
            self.id = id
            self.title = title
            self.value = value
        }
    }

    public var title: String
    public var leadingLabel: String
    public var trailingLabel: String
    public var details: [Detail]

    public init(
        title: String,
        leadingLabel: String,
        trailingLabel: String,
        details: [Detail] = []
    ) {
        self.title = title
        self.leadingLabel = leadingLabel
        self.trailingLabel = trailingLabel
        self.details = details
    }

    public var accessibilityValue: String {
        ([title, leadingLabel, trailingLabel]
            + details.map { "\($0.title) \($0.value)" })
            .filter { $0.isEmpty == false }
            .joined(separator: ". ")
    }
}
