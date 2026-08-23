/// Which block the player panel is showing.
///
/// The panel used to serialize every change through three ordered phases. That
/// model forced an empty-shell frame by construction. The reference animation
/// never shows one: the chrome morphs while both layers crossfade in the same
/// window. This value object only records which aside is selected, so SwiftUI
/// can retarget an in-flight animation when the wearer changes their mind.
public struct PlaybackPanelExpansion: Equatable, Sendable {
    /// The block the panel is sized to show.
    public enum Layout: Equatable, Sendable, CaseIterable {
        case collapsed
        case timeline
        case settings
        case mediaInformation
    }

    public private(set) var layout: Layout

    public init(_ layout: Layout = .collapsed) {
        self.layout = layout
    }

    /// Whether the panel is showing anything beyond its collapsed form.
    public var isExpanded: Bool { layout != .collapsed }

    /// Whether `candidate` is the block currently selected. Button selected
    /// state follows this directly, so it does not flicker through an
    /// intermediate value.
    public func isShowing(_ candidate: Layout) -> Bool { layout == candidate }

    /// Switches directly to `requested`. When called mid-animation SwiftUI
    /// retargets the in-flight interpolation rather than queueing behind it.
    public mutating func request(_ requested: Layout) {
        guard requested != layout else { return }
        layout = requested
    }

    /// Pressing the block already showing collapses the panel.
    public mutating func toggle(_ layout: Layout) {
        request(self.layout == layout ? .collapsed : layout)
    }
}

/// Compatibility alias introduced by the redesign; the synthesis refers to this
/// name. It is the same value object as `PlaybackPanelExpansion`.
public typealias PlaybackPanelLayout = PlaybackPanelExpansion
