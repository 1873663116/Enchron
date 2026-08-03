/// The observed readiness of a RealityKit surface for a requested playback presentation.
///
/// `rawValue` is persisted in PlaybackCore's versioned presentation-state diagnostic
/// artifact, so these values remain stable for existing evidence readers.
public enum PlaybackPresentationSettlementPhase: String, Codable, Sendable {
    /// The renderer is bound to the target RealityKit surface.
    case surfaceAttached

    /// The target RealityKit surface has reported all required observed facts as ready.
    case settled
}
