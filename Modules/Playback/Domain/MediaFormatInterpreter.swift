enum MediaFormatInterpreter {
    typealias Projection = PlaybackModel.ProjectionType

    struct SourceSignaling: Equatable, Sendable {
        let providerProjectionKind: String?
        let sampleProjectionKind: String?
        let providerViewPackingKind: String?
        let sampleViewPackingKind: String?
        let isMVHEVC: Bool
    }

    struct EncodedVideoGeometry: Equatable, Sendable {
        let width: Int
        let height: Int
        let horizontalSpacing: Int
        let verticalSpacing: Int
    }

    static func sourceFormat(from signaling: SourceSignaling) -> SourceMediaFormatFact {
        let contentKind =
            recognizedContentKind(from: signaling.providerProjectionKind)
            ?? recognizedContentKind(from: signaling.sampleProjectionKind)
            ?? (signaling.isMVHEVC ? .spatialVideo : .rectilinear)
        let stereoLayout = stereoLayout(
            providerValue: signaling.providerViewPackingKind,
            sampleValue: signaling.sampleViewPackingKind,
            isMVHEVC: signaling.isMVHEVC
        )
        return sourceFormat(
            contentKind: contentKind,
            stereoLayout: stereoLayout
        )
    }

    static func sourceFormat(
        contentKind: PlaybackModel.SourceVideoContentKind,
        stereoLayout: PlaybackModel.StereoLayout
    ) -> SourceMediaFormatFact {
        let projection = projection(for: contentKind)
        return SourceMediaFormatFact(
            contentKind: contentKind,
            projection: projection,
            horizontalFieldOfViewDegrees: sourceHorizontalFieldOfViewDegrees(
                for: projection
            ),
            stereoLayout: stereoLayout
        )
    }

    static func mediaFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int?,
        stereoLayout: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool
    ) -> MediaFormat {
        MediaFormat(
            projection: mediaProjection(from: projection),
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereoLayout: mediaStereoLayout(from: stereoLayout),
            usesDolbyVisionFallback: usesDolbyVisionFallback
        )
    }

    static func playbackProjection(
        from projection: MediaProjection
    ) -> PlaybackModel.ProjectionType {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    static func playbackStereoLayout(
        from stereoLayout: MediaStereoLayout
    ) -> PlaybackModel.StereoLayout {
        switch stereoLayout {
        case .mono: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }

    static func normalizedHorizontalFieldOfViewDegrees(
        for projection: PlaybackModel.ProjectionType,
        explicitDegrees: Int?
    ) -> Int? {
        guard projection == .customAngle else { return nil }
        return PanoramaHorizontalCoverage.normalized(
            explicitDegrees ?? PanoramaHorizontalCoverage.defaultCustomAngle
        )
    }

    static func effectiveHorizontalFieldOfViewDegrees(
        for projection: PlaybackModel.ProjectionType,
        explicitDegrees: Int?
    ) -> Int {
        switch projection {
        case .flat:
            PanoramaHorizontalCoverage.defaultCustomAngle
        case .equirectangular180:
            180
        case .equirectangular360:
            360
        case .customAngle:
            PanoramaHorizontalCoverage.normalized(
                explicitDegrees ?? PanoramaHorizontalCoverage.defaultCustomAngle
            )
        }
    }

    static func projection(from value: String) -> PlaybackModel.ProjectionType? {
        let normalized = normalized(value)
        if normalized.contains("halfequirectangular") { return .equirectangular180 }
        if normalized.contains("equirectangular") { return .equirectangular360 }
        if normalized.contains("fisheye")
            || normalized.contains("parametricimmersive")
            || normalized.contains("appleimmersivevideo") {
            return .flat
        }
        if normalized.contains("rectilinear") { return .flat }
        return nil
    }

    static func stereoLayout(
        from value: String,
        isMVHEVC: Bool = false
    ) -> PlaybackModel.StereoLayout? {
        if isMVHEVC { return .multiview }
        let normalized = normalized(value)
        if normalized.contains("sidebyside") || normalized.contains("leftright") {
            return .sideBySide
        }
        if normalized.contains("overunder") || normalized.contains("topbottom") {
            return .topBottom
        }
        return nil
    }

    private static func stereoLayout(
        providerValue: String?,
        sampleValue: String?,
        isMVHEVC: Bool
    ) -> PlaybackModel.StereoLayout {
        if isMVHEVC { return .multiview }
        return stereoLayout(from: providerValue ?? "")
            ?? stereoLayout(from: sampleValue ?? "")
            ?? .mono
    }

    private static func recognizedContentKind(
        from projectionKind: String?
    ) -> PlaybackModel.SourceVideoContentKind? {
        let normalizedProjection = normalized(projectionKind ?? "")
        if normalizedProjection.contains("appleimmersivevideo") {
            return .appleImmersiveVideo
        }
        if normalizedProjection.contains("parametricimmersive")
            || normalizedProjection.contains("fisheye") {
            return .parametricImmersive
        }
        if normalizedProjection.contains("halfequirectangular") {
            return .halfEquirectangular
        }
        if normalizedProjection.contains("equirectangular") {
            return .equirectangular
        }
        if normalizedProjection.contains("rectilinear") {
            return .rectilinear
        }
        return nil
    }

    private static func projection(
        for contentKind: PlaybackModel.SourceVideoContentKind
    ) -> PlaybackModel.ProjectionType {
        switch contentKind {
        case .halfEquirectangular: .equirectangular180
        case .equirectangular: .equirectangular360
        case .rectilinear, .spatialVideo, .parametricImmersive, .appleImmersiveVideo:
            .flat
        }
    }

    private static func sourceHorizontalFieldOfViewDegrees(
        for projection: PlaybackModel.ProjectionType
    ) -> Int? {
        switch projection {
        case .flat:
            nil
        case .equirectangular180:
            180
        case .equirectangular360:
            360
        case .customAngle:
            PanoramaHorizontalCoverage.defaultCustomAngle
        }
    }

    private static func mediaProjection(
        from projection: PlaybackModel.ProjectionType
    ) -> MediaProjection {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func mediaStereoLayout(
        from stereoLayout: PlaybackModel.StereoLayout
    ) -> MediaStereoLayout {
        switch stereoLayout {
        case .mono, .multiview: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func parseResolution(
        _ dimensions: String
    ) -> PlaybackModel.MediaProfile.Resolution? {
        let values = dimensions
            .split(whereSeparator: { $0 == "x" || $0 == "×" })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 2 else { return nil }
        return .init(width: values[0], height: values[1])
    }

    static func stereoLayoutDisplayName(
        _ stereoLayout: PlaybackModel.StereoLayout
    ) -> String {
        switch stereoLayout {
        case .mono: "Mono"
        case .multiview: "Native Stereo"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }

    static func mediaProfile(
        projectionKind: String,
        viewPackingKind: String,
        isMVHEVC: Bool,
        dimensions: String,
        encodedGeometry: EncodedVideoGeometry?,
        transferFunction: String,
        dolbyVisionProfile: Int,
        formatHasDvcC: Bool,
        formatHasDvvC: Bool,
        dolbyVisionCrossCompatibilityID: Int,
        dolbyVisionHasEnhancementLayer: Bool,
        codecName: String,
        nominalFrameRate: Double,
        durationSeconds: Double,
        fallback: PlaybackModel.MediaProfile?
    ) -> PlaybackModel.MediaProfile? {
        let resolution: PlaybackModel.MediaProfile.Resolution?
        let pixelAspectRatio: PlaybackModel.MediaProfile.PixelAspectRatio
        if let encodedGeometry {
            resolution = .init(
                width: encodedGeometry.width,
                height: encodedGeometry.height
            )
            pixelAspectRatio = .init(
                horizontalSpacing: encodedGeometry.horizontalSpacing,
                verticalSpacing: encodedGeometry.verticalSpacing
            )
        } else {
            resolution = parseResolution(dimensions)
            pixelAspectRatio = .square
        }
        guard let resolution else {
            return fallback
        }
        let transfer = transferFunction.lowercased()
        let baseLayer: PlaybackModel.HDRType
        if transfer.contains("2084") || transfer.contains("pq") {
            baseLayer = .hdr10
        } else if transfer.contains("hlg") || transfer.contains("arib") {
            baseLayer = .hlg
        } else {
            baseLayer = .sdr
        }
        let claimsDolbyVision = dolbyVisionProfile > 0
            || formatHasDvcC
            || formatHasDvvC
        let dolbyVision: PlaybackModel.DolbyVision? = claimsDolbyVision
            ? PlaybackModel.DolbyVision(
                profile: dolbyVisionProfile,
                crossCompatibilityID: dolbyVisionCrossCompatibilityID,
                fallbackTo: dolbyVisionHasEnhancementLayer ? baseLayer : nil
            )
            : nil
        let hdr: PlaybackModel.HDRType = claimsDolbyVision
            && dolbyVisionHasEnhancementLayer == false
            ? .dolbyVision
            : baseLayer
        return PlaybackModel.MediaProfile(
            projectionType: projection(from: projectionKind)
                ?? fallback?.projectionType
                ?? .flat,
            stereoLayout: stereoLayout(from: viewPackingKind, isMVHEVC: isMVHEVC)
                ?? fallback?.stereoLayout
                ?? .mono,
            hdrType: hdr,
            dolbyVision: dolbyVision,
            resolution: resolution,
            pixelAspectRatio: pixelAspectRatio,
            frameRate: nominalFrameRate,
            videoCodec: codecName,
            durationSeconds: durationSeconds
        )
    }
}

extension PlaybackRuntime {
    public var effectiveProjectionType: PlaybackModel.ProjectionType {
        selectedProjectionType
    }

    public var effectiveHorizontalFieldOfViewDegrees: Int {
        MediaFormatInterpreter.effectiveHorizontalFieldOfViewDegrees(
            for: selectedProjectionType,
            explicitDegrees: selectedHorizontalFieldOfViewDegrees
        )
    }

    public func setFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int? = nil,
        stereo: PlaybackModel.StereoLayout,
        usesDolbyVisionFallback: Bool = false
    ) async throws {
        guard mediaKind == .video else {
            throw RuntimeError.audioOnlyRequiresWindowPresentation
        }
        adoptUserFormat(
            projection: projection,
            horizontalFieldOfViewDegrees:
                MediaFormatInterpreter.normalizedHorizontalFieldOfViewDegrees(
                    for: projection,
                    explicitDegrees: horizontalFieldOfViewDegrees
                ),
            stereo: stereo,
            usesDolbyVisionFallback: usesDolbyVisionFallback
        )
    }
}
