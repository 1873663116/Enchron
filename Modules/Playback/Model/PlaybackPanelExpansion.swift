public struct PlaybackPanelExpansion: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        case collapsed
        case timeline
        case settings
        case mediaInformation
    }

    public private(set) var layout: Layout

    public init(_ layout: Layout = .collapsed) {
        self.layout = layout
    }

    public var isExpanded: Bool { layout != .collapsed }

    public func isShowing(_ layout: Layout) -> Bool { self.layout == layout }

    public mutating func request(_ requested: Layout) {
        layout = requested
    }

    public mutating func toggle(_ layout: Layout) {
        request(self.layout == layout ? .collapsed : layout)
    }
}
