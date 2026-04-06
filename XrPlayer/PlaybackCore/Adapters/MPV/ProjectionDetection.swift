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
    /// Priority: GSpherical metadata > fisheye > fallback to flat.
    /// Stereoscopic layout (SBS/OU) is expressed via StereoLayout axis, not ProjectionType.
    /// Aspect ratio alone is NOT sufficient to infer panoramic content (per TESTING.md).
    ///
    /// NOTE: Stereo detection (SBS/OU → StereoLayout) is implemented in Unit 3.
    /// This function returns .flat for stereo-flagged content until Unit 3 lands.
    static func detect(from input: ProjectionDetectionInput) -> PlaybackCoreDomain.ProjectionType {
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
                return .equirectangular180
            }
            if projType.contains("cubemap") {
                return .equirectangular360
            }
            // Default spherical = 360
            return .equirectangular360
        }

        // 3. No metadata markers → flat (do not guess from aspect ratio alone)
        // NOTE: stereo3dIn tags (sbs/ou) will be handled by StereoLayout detection in Unit 3.
        return .flat
    }
}
