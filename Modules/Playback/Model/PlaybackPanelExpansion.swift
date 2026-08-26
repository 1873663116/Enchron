/// Which block the player panel is showing, and where it is in a change between two
/// of them.
public struct PlaybackPanelExpansion: Equatable, Sendable {
    /// The block the panel is sized to show.
    public enum Layout: Equatable, Sendable {
        case collapsed
        case timeline
        case settings
        case mediaInformation
    }

    /// Which of the three ordered steps the panel is in.
    public enum Phase: Equatable, Sendable {
        /// Contents visible, at the size that fits them.
        case settled
        /// Contents on their way out. The shell still holds the size being left.
        case contentLeaving
        /// The empty shell is travelling to the size being entered.
        case resizing
    }

    /// The size the shell currently holds, which is the layout being left until the
    /// contents have gone and the layout being entered from then on. Deciding what to
    /// put in the hierarchy from this is what gives the shell a height to travel to.
    public private(set) var layout: Layout

    public private(set) var phase: Phase

    private var target: Layout

    public init(_ layout: Layout = .collapsed) {
        self.layout = layout
        self.phase = .settled
        self.target = layout
    }

    /// Whether the contents belong on screen. False for both of the steps that leave
    /// the wearer looking at an empty shell.
    public var contentIsVisible: Bool { phase == .settled }

    /// Whether the panel is showing anything beyond its collapsed form, which is what
    /// decides its width.
    public var isExpanded: Bool { layout != .collapsed }

    /// Whether `layout` is the block the panel is settling into. A button's selected
    /// state follows this rather than `layout`, so it does not flicker back for the
    /// length of the contents leaving.
    public func isShowing(_ layout: Layout) -> Bool { target == layout }

    /// Begins a change toward `requested`. A request that arrives mid-change retargets
    /// it rather than queueing behind it, so a wearer who changes their mind is not
    /// made to sit through the change they abandoned. Re-entering `contentLeaving`
    /// while the shell is already empty costs nothing on screen and keeps this free of
    /// per-phase special cases.
    public mutating func request(_ requested: Layout) {
        guard requested != target else { return }
        target = requested
        phase = .contentLeaving
    }

    /// Presses of a block's own button collapse the panel when that block is the one
    /// already showing.
    public mutating func toggle(_ layout: Layout) {
        request(target == layout ? .collapsed : layout)
    }

    /// Moves to the next step. `completed` is the step the caller animated, so a
    /// completion that lands after a newer request has already moved the panel on is
    /// ignored instead of skipping a step.
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
