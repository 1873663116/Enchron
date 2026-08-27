public struct PlaybackPanelExpansion: Equatable, Sendable {
    public enum Layout: Equatable, Sendable {
        case collapsed
        case timeline
        case settings
        case mediaInformation
    }

    public enum Phase: Equatable, Sendable {
        case settled
        case contentLeaving
        case resizing
    }

    public private(set) var layout: Layout

    public private(set) var phase: Phase

    private var target: Layout

    public init(_ layout: Layout = .collapsed) {
        self.layout = layout
        self.phase = .settled
        self.target = layout
    }

    public var contentIsVisible: Bool { phase == .settled }

    public var isExpanded: Bool { layout != .collapsed }

    public func isShowing(_ layout: Layout) -> Bool { target == layout }

    public mutating func request(_ requested: Layout) {
        guard requested != target else { return }
        target = requested
        phase = .contentLeaving
    }

    public mutating func toggle(_ layout: Layout) {
        request(target == layout ? .collapsed : layout)
    }

    public mutating func advance(from completed: Phase) {
        guard phase == completed else { return }
        switch completed {
        case .settled:
            break
        case .contentLeaving:
            layout = target
            phase = .resizing
        case .resizing:
            phase = .settled
        }
    }
}
