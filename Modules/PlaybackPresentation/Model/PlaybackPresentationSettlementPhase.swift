/// The observed readiness of a RealityKit surface for a requested playback presentation.
///
/// `rawValue` is persisted in PlaybackCore's versioned presentation-state diagnostic
/// artifact, so these values remain stable for existing evidence readers.
public enum PlaybackPresentationSettlementPhase: String, Codable, Sendable {
    /// The renderer is bound to the target RealityKit surface.
    case surfaceAttached

    /// A visionOS Simulator verified desired panorama configuration, but cannot expose
    /// the actual rendering-ready facts required for device acceptance.
    case simulatorConfigured

    /// The target RealityKit surface has reported all required observed facts as ready.
    case settled
}
