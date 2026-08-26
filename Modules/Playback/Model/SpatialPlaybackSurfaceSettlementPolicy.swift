
public enum SpatialPlaybackSurfaceSettlementPolicy {
    public nonisolated static func contentTypeMatches(
        projection: PlaybackModel.ProjectionType,
        sourceContentKind: PlaybackModel.SourceVideoContentKind,
        provenance: MediaFormatProvenance,
        observedContentType: String
    ) -> Bool {
        let contentType = observedContentType
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if provenance == .source {
            return switch sourceContentKind {
            case .halfEquirectangular: contentType == "halfequirectangular"
            case .equirectangular: contentType == "equirectangular"
            case .parametricImmersive: contentType == "parametricimmersive"
            case .appleImmersiveVideo: contentType == "immersive"
            case .rectilinear, .spatialVideo: false
            }
        }
        return switch projection {
        case .flat:
            false
        case .equirectangular360:
            contentType == "equirectangular"
        case .equirectangular180:
            contentType == "halfequirectangular"
        case .customAngle:
            contentType == "equirectangular"
        }
    }

    public nonisolated static func viewingModeMatches(
        stereoLayout: PlaybackModel.StereoLayout,
        observedViewingMode: String?,
        requiresObservedMode: Bool = false
    ) -> Bool {
        let viewingMode = observedViewingMode?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        switch stereoLayout {
        case .mono:
            return viewingMode == "mono"
                || (viewingMode == nil && requiresObservedMode == false)
        case .multiview, .sideBySide, .topBottom:
            return viewingMode == "stereo"
        }
    }

    /// Confirms a user override without depending on ContentTypeDidChange.
    /// That event is classification evidence when delivered, but RealityKit
    /// does not replay it for every fresh component. The accepted renderer
    /// description plus RealityKit's actual projection and eye modes form the
    /// equivalent adoption proof for an explicit override.
    public nonisolated static func explicitOverrideAdoptionIsConfirmed(
        projection: PlaybackModel.ProjectionType,
        stereoLayout: PlaybackModel.StereoLayout,
        provenance: MediaFormatProvenance,
        acceptedRendererProjectionKind: String?,
        desiredImmersiveViewingMode: String,
        observedImmersiveViewingMode: String?,
        observedViewingMode: String?
    ) -> Bool {
        guard provenance == .userOverride else { return false }
        let acceptedProjection = acceptedRendererProjectionKind?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let rendererProjectionMatches = switch projection {
        case .flat:
            false
        case .equirectangular180:
            acceptedProjection == "halfequirectangular"
        case .equirectangular360, .customAngle:
            acceptedProjection == "equirectangular"
        }
        return rendererProjectionMatches
            && immersiveViewingModeMatches(
                contentIsPanoramic: true,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: desiredImmersiveViewingMode,
                observedImmersiveViewingMode: observedImmersiveViewingMode
            )
            && viewingModeMatches(
                stereoLayout: stereoLayout,
                observedViewingMode: observedViewingMode,
                requiresObservedMode: true
            )
    }

    public nonisolated static func immersiveViewingModeMatches(
        contentIsPanoramic: Bool,
        requiresTransitionConfirmation: Bool,
        desiredImmersiveViewingMode: String,
        observedImmersiveViewingMode: String?
    ) -> Bool {
        guard contentIsPanoramic, requiresTransitionConfirmation else {
            return true
        }
        let desiredMode = desiredImmersiveViewingMode
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let observedMode = observedImmersiveViewingMode?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return observedMode == desiredMode
    }
}
