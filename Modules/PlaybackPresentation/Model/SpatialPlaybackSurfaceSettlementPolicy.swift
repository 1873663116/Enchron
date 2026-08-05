import PlaybackFeature

public enum PanoramaTargetBootstrapState: Equatable {
    case awaitingPortalActivation
    case requestingProgressive
    case progressiveConfirmed

    public mutating func receivePortalActivation() -> Bool {
        guard self == .awaitingPortalActivation else { return false }
        self = .requestingProgressive
        return true
    }

    public mutating func receiveProgressiveChange() {
        guard self == .requestingProgressive else { return }
        self = .progressiveConfirmed
    }
}

public enum SpatialPlaybackSurfaceSettlementPolicy {
    public nonisolated static func contentTypeMatches(
        projection: PlaybackModel.ProjectionType,
        observedContentType: String
    ) -> Bool {
        let contentType = observedContentType
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        switch projection {
        case .flat:
            return false
        case .equirectangular360:
            return contentType == "equirectangular"
        case .equirectangular180:
            return contentType == "halfequirectangular"
        case .fisheye:
            return contentType == "parametricimmersive"
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
        case .sideBySide, .topBottom:
            return viewingMode == "stereo"
        }
    }

    public nonisolated static func immersiveViewingModeMatches(
        projection: PlaybackModel.ProjectionType,
        requiresTransitionConfirmation: Bool,
        desiredImmersiveViewingMode: String,
        observedImmersiveViewingMode: String?
    ) -> Bool {
        guard projection != .flat, requiresTransitionConfirmation else {
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
