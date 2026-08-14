import CoreMedia
import Foundation

public struct PlaybackVideoGeometry: Sendable, Equatable {
    public struct EncodedDimensions: Sendable, Equatable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = max(0, width)
            self.height = max(0, height)
        }
    }

    public struct SampleAspectRatio: Sendable, Equatable {
        public static let square = SampleAspectRatio(horizontalSpacing: 1, verticalSpacing: 1)

        public let horizontalSpacing: Int
        public let verticalSpacing: Int

        public init(horizontalSpacing: Int, verticalSpacing: Int) {
            if horizontalSpacing > 0, verticalSpacing > 0 {
                self.horizontalSpacing = horizontalSpacing
                self.verticalSpacing = verticalSpacing
            } else {
                self = .square
            }
        }
    }

    public let encodedDimensions: EncodedDimensions
    public let sampleAspectRatio: SampleAspectRatio

    public init(
        encodedDimensions: EncodedDimensions,
        sampleAspectRatio: SampleAspectRatio
    ) {
        self.encodedDimensions = encodedDimensions
        self.sampleAspectRatio = sampleAspectRatio
    }
}

extension PlaybackVideoGeometry {
    init(formatDescription: CMVideoFormatDescription) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let extensions = CMFormatDescriptionGetExtensions(formatDescription)
            as? [String: Any] ?? [:]
        let ratio = extensions[
            kCMFormatDescriptionExtension_PixelAspectRatio as String
        ] as? [String: Any]
        let horizontal = ratio?[
            kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String
        ] as? NSNumber
        let vertical = ratio?[
            kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String
        ] as? NSNumber
        self.init(
            encodedDimensions: .init(
                width: Int(dimensions.width),
                height: Int(dimensions.height)
            ),
            sampleAspectRatio: .init(
                horizontalSpacing: horizontal?.intValue ?? 1,
                verticalSpacing: vertical?.intValue ?? 1
            )
        )
    }
}

public struct PlaybackDiagnostics: Sendable, Equatable {
    public var codecName = "unknown"
    public var isMVHEVC = false
    public var currentSeconds = 0.0
    public var durationSeconds = 0.0
    public var nominalFrameRate = 0.0
    public var enqueuedSampleCount = 0
    public var timelineConfiguredBeforeFirstEnqueue: Bool?
    public var sourcePixelFormat = "----"
    public var destinationPixelFormat = "----"
    public var dimensions = "—"
    public var videoGeometry: PlaybackVideoGeometry?
    public var colorPrimaries = "—"
    public var transferFunction = "—"
    public var yCbCrMatrix = "—"
    public var range = "—"
    public var projectionKind = "missing"
    public var viewPackingKind = "missing"
    public var hasLeftStereoEyeView = false
    public var hasRightStereoEyeView = false
    public var sourceBufferHasMasteringDisplayMetadata = false
    public var sourceBufferHasContentLightLevelMetadata = false
    public var trackFormatHasMasteringDisplayMetadata = false
    public var trackFormatHasContentLightLevelMetadata = false
    public var sourceFormatHasMasteringDisplayMetadata = false
    public var sourceFormatHasContentLightLevelMetadata = false
    public var destinationBufferHasMasteringDisplayMetadata = false
    public var destinationBufferHasContentLightLevelMetadata = false
    public var formatHasHvcC = false
    /// Read from every video stream in the source, because Dolby Vision Profile 7
    /// keeps its configuration record on the enhancement stream rather than on the
    /// base layer that gets decoded. Zero means the source claims no Dolby Vision.
    public var dolbyVisionProfile = 0
    public var dolbyVisionCrossCompatibilityID = 0
    /// A two-layer source delivers only its base layer, so this is what separates the
    /// Dolby Vision a source claims from the picture the wearer receives.
    public var dolbyVisionHasEnhancementLayer = false
    public var formatHasDvcC = false
    public var formatHasDvvC = false
    public var formatHasAmbientViewingEnvironment = false
    public var rendererStatus = "unknown"
    public var rendererError = "none"
    /// Whether the exact sample accepted by the video renderer still carries
    /// both eye views. Nil means no renderer input has published this fact yet.
    public var rendererInputIsMultiview: Bool?
    /// Audio can leave the active graph while video continues.
    public var audioRetired = false
    public var audioRetirementReason: String?
    /// A video renderer failure is separate from its diagnostic error text so
    /// product surfaces never need to interpret framework wording.
    public var rendererFailedToDecode = false
    public var rendererTotalFrameCount: Int?
    public var rendererDroppedFrameCount: Int?
    public var rendererCorruptedFrameCount: Int?
    public var rendererOptimizedCompositingFrameCount: Int?
    public var rendererAccumulatedFrameDelaySeconds: TimeInterval?
    public var rendererPerformanceMetricsObservationCount: UInt64 = 0

    public init() {}

    public var estimatedFrameNumber: Int {
        let estimate = currentSeconds * nominalFrameRate
        guard nominalFrameRate > 0, estimate.isFinite else { return 0 }
        return Int(estimate.rounded())
    }

    public var timecode: String {
        "\(Self.formatTime(currentSeconds)) / \(Self.formatTime(durationSeconds))"
    }

    public var compactSummary: String {
        "\(timecode)  •  frame ≈ \(estimatedFrameNumber)  •  \(sourcePixelFormat) → \(destinationPixelFormat)  •  \(colorPrimaries) / \(transferFunction) / \(range)"
    }

    public var snapshotText: String {
        """
        codec: \(codecName)
        mvHEVC: \(isMVHEVC)
        time: \(String(format: "%.6f", currentSeconds)) s / \(String(format: "%.6f", durationSeconds)) s
        estimatedFrame: \(estimatedFrameNumber) @ \(String(format: "%.3f", nominalFrameRate)) fps
        enqueuedSamples: \(enqueuedSampleCount)
        timelineConfiguredBeforeFirstEnqueue: \(timelineConfiguredBeforeFirstEnqueue.map { String($0) } ?? "notObserved")
        pixelFormat: \(sourcePixelFormat) -> \(destinationPixelFormat)
        dimensions: \(dimensions)
        sampleAspectRatio: \(videoGeometry.map {
            "\($0.sampleAspectRatio.horizontalSpacing):\($0.sampleAspectRatio.verticalSpacing)"
        } ?? "notObserved")
        color: primaries=\(colorPrimaries), transfer=\(transferFunction), matrix=\(yCbCrMatrix), range=\(range)
        spatialFormat: projection=\(projectionKind), packing=\(viewPackingKind), leftEye=\(hasLeftStereoEyeView), rightEye=\(hasRightStereoEyeView)
        hdrMetadata.sourceBuffer: masteringDisplay=\(sourceBufferHasMasteringDisplayMetadata), contentLightLevel=\(sourceBufferHasContentLightLevelMetadata)
        hdrMetadata.trackFormat: masteringDisplay=\(trackFormatHasMasteringDisplayMetadata), contentLightLevel=\(trackFormatHasContentLightLevelMetadata)
        hdrMetadata.sourceFormat: masteringDisplay=\(sourceFormatHasMasteringDisplayMetadata), contentLightLevel=\(sourceFormatHasContentLightLevelMetadata)
        hdrMetadata.destinationBuffer: masteringDisplay=\(destinationBufferHasMasteringDisplayMetadata), contentLightLevel=\(destinationBufferHasContentLightLevelMetadata)
        compressedFormat: hvcC=\(formatHasHvcC), dvcC=\(formatHasDvcC), dvvC=\(formatHasDvvC), amve=\(formatHasAmbientViewingEnvironment)
        renderer: status=\(rendererStatus), error=\(rendererError)
        rendererInputIsMultiview: \(rendererInputIsMultiview.map(String.init) ?? "notObserved")
        audioRetired: \(audioRetired), reason=\(audioRetirementReason ?? "none")
        rendererFailedToDecode: \(rendererFailedToDecode)
        rendererPerformance: \(rendererPerformanceSummary)
        """
    }

    private var rendererPerformanceSummary: String {
        let totalFrames = rendererTotalFrameCount.map { String($0) } ?? "notObserved"
        let droppedFrames = rendererDroppedFrameCount.map { String($0) } ?? "notObserved"
        let corruptedFrames = rendererCorruptedFrameCount.map { String($0) }
            ?? "notObserved"
        let optimizedFrames = rendererOptimizedCompositingFrameCount.map { String($0) }
            ?? "notObserved"
        let accumulatedDelay = rendererAccumulatedFrameDelaySeconds.map { String($0) }
            ?? "notObserved"
        return "totalFrames=\(totalFrames), droppedFrames=\(droppedFrames), "
            + "corruptedFrames=\(corruptedFrames), "
            + "optimizedCompositingFrames=\(optimizedFrames), "
            + "accumulatedFrameDelaySeconds=\(accumulatedDelay), "
            + "observationCount=\(rendererPerformanceMetricsObservationCount)"
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--.---" }
        let minutes = Int(seconds) / 60
        return String(format: "%02d:%06.3f", minutes, seconds - Double(minutes * 60))
    }
}

func fourCC(_ value: OSType) -> String {
    let bytes: [UInt8] = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? String(format: "0x%08X", value)
}
