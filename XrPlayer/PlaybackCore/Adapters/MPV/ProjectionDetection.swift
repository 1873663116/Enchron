import Foundation

/// Input snapshot for projection type detection.
/// All fields come from mpv properties and container metadata,
/// captured once after media profile is detected.
struct ProjectionDetectionInput: Equatable {
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

enum ProjectionDetection {
    /// Pure function: infer projection type from mpv metadata.
    /// Priority: stereo3d tags > GSpherical metadata > fallback to flat.
    /// Aspect ratio alone is NOT sufficient to infer panoramic content (per TESTING.md).
    static func detect(from input: ProjectionDetectionInput) -> PlaybackCoreDomain.ProjectionType {
        let stereo = input.stereo3dIn.lowercased().trimmingCharacters(in: .whitespaces)

        // 1. Stereoscopic layout detection (highest priority)
        if stereo.contains("sbs") || stereo == "side_by_side_left" || stereo == "side_by_side_right" {
            return .stereoscopicSBS
        }
        // mpv stereo3d over-under tags: "ab2l", "ab2r", "abl", "abr",
        // "over_under_left", "over_under_right", "top_bottom" variants.
        // Match only known mpv tag prefixes to avoid false positives on unrelated strings.
        if stereo.hasPrefix("ab") || stereo.hasPrefix("ou")
            || stereo.contains("top_bottom") || stereo.contains("over_under") {
            return .stereoscopicOU
        }

        // 2. GSpherical metadata detection
        let isSpherical = input.gSphericalSpherical?.lowercased() == "true"
        let projType = input.gSphericalProjectionType?.lowercased() ?? ""

        // Fisheye projection detection (before general spherical)
        if projType.contains("fisheye") || projType.contains("equidistant") {
            return .fisheye
        }

        if isSpherical || projType.contains("equirectangular") || projType.contains("cubemap") {
            // Check FOV to distinguish 180 vs 360
            if let fov = input.horizontalFOVDegrees, fov > 0, fov <= 180 {
                return .panorama180
            }
            if projType.contains("cubemap") {
                return .panorama360
            }
            // Default spherical = 360
            return .panorama360
        }

        // 3. No metadata markers → flat (do not guess from aspect ratio alone)
        return .flat
    }
}
