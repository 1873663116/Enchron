import Foundation

nonisolated extension FileBrowsingDomain {
    /// Content filter categories for narrowing file listings.
    ///
    /// Currently UI-only: MediaFile does not carry resolution/HDR/spatial attributes.
    /// Filter logic will be wired when MediaProfile metadata becomes available in FileBrowsing.
    public enum ContentFilter: String, Sendable, Hashable, CaseIterable {
        case all
        case fourK = "4K"
        case hdr = "HDR"
        case spatial = "Spatial"

        public var displayName: String { rawValue == "all" ? "All" : rawValue }
    }
}
