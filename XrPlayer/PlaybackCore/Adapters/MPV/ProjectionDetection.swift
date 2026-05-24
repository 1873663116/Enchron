import Foundation

/// Input snapshot for projection type detection.
/// All fields come from mpv properties and container metadata,
/// captured once after media profile is detected.
nonisolated struct ProjectionDetectionInput: Equatable, Sendable {
    /// mpv `video-params/stereo-in` or `video-params/stereo3d-in` — stereoscopic layout tag.
    /// Empty string means mono (no stereo layout).
    let stereo3dIn: String

    /// Container-level spherical metadata: `metadata/by-key/GSpherical:Spherical`.
    /// "true" if the container has Google Spherical Metadata.
    let gSphericalSpherical: String?

    /// Container-level spherical projection type: `metadata/by-key/GSpherical:ProjectionType`.
    /// e.g. "equirectangular"
    let gSphericalProjectionType: String?

    /// Container-level spherical full-pano width FOV in degrees.
    /// `metadata/by-key/GSpherical:FullPanoWidthPixels` or HFOV tag.
    /// nil means not specified (assume 360 if spherical).
    let horizontalFOVDegrees: Double?

    /// Video width / height ratio.
    let aspectRatio: Double?
}

nonisolated enum ProjectionDetection {
    /// Pure function: infer projection type and stereo layout from mpv metadata.
    ///
    /// Returns a tuple `(ProjectionType, StereoLayout)`.
    ///
    /// Detection order:
    /// 1. Stereo layout from `stereo3dIn` (exact mpv value matching only).
    /// 2. GSpherical metadata → overrides projectionType (fisheye forces stereoLayout = .mono).
    /// 3. No metadata markers → (.flat, derived stereoLayout).
    ///
    /// Stereo exact values (from mpv `mp_stereo3d_names[]`):
    ///   - `"sbs2l"` / `"sbs2r"` → .sideBySide
    ///   - `"ab2l"`  / `"ab2r"`  → .topBottom
    ///   - All others (`"mono"`, `""`, `"no"`, unsupported formats) → .mono
    ///
    /// Aspect ratio alone is NOT sufficient to infer panoramic content (per TESTING.md).
    static func detect(from input: ProjectionDetectionInput) -> (
        PlaybackCoreDomain.ProjectionType, PlaybackCoreDomain.StereoLayout
    ) {
        // 1. Stereo layout detection — exact mpv value matching only.
        let stereo = input.stereo3dIn.lowercased().trimmingCharacters(in: .whitespaces)
        let stereoLayout: PlaybackCoreDomain.StereoLayout
        if stereo == "sbs2l" || stereo == "sbs2r" {
            stereoLayout = .sideBySide
        } else if stereo == "ab2l" || stereo == "ab2r" {
            stereoLayout = .topBottom
        } else {
            // Covers "mono", "", "no", and any unsupported mpv stereo3d format.
            stereoLayout = .mono
        }

        // 2. GSpherical metadata detection — overrides projectionType.
        let isSpherical = input.gSphericalSpherical?.lowercased() == "true"
        let projType = input.gSphericalProjectionType?.lowercased() ?? ""

        // Fisheye projection forces stereoLayout = .mono (fisheye is always mono).
        if projType.contains("fisheye") || projType.contains("equidistant") {
            return (.fisheye, .mono)
        }

        if isSpherical || projType.contains("equirectangular") || projType.contains("cubemap") {
            // Check FOV to distinguish 180 vs 360.
            if let fov = input.horizontalFOVDegrees, fov > 0, fov <= 180 {
                return (.equirectangular180, stereoLayout)
            }
            if projType.contains("cubemap") {
                return (.equirectangular360, stereoLayout)
            }
            // Default spherical = 360.
            return (.equirectangular360, stereoLayout)
        }

        // 3. No metadata markers → flat (do not guess from aspect ratio alone).
        return (.flat, stereoLayout)
    }
}
