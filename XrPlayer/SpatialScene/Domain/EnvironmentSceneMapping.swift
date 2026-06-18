import Foundation

/// Maps a featured-environment card to the 3D scene loaded in the immersive space.
///
/// The art repository currently ships a single exported `world` scene, so every
/// card resolves to it (cards are cosmetic selectors over one world for now). The
/// mapping is total — it never returns nil — so the immersive entry path always
/// has a scene to load. When the art repo ships per-environment worlds this gains
/// real branching.
public nonisolated enum EnvironmentSceneMapping {
    /// The single art-exported scene entity name loaded from the main bundle.
    public static let worldSceneName = "world"

    /// Resolve a card's environment id to its scene entity name. Always non-nil.
    public static func sceneName(forEnvironmentID id: String) -> String {
        worldSceneName
    }
}
