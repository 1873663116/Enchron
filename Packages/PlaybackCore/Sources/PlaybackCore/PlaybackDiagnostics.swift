import CoreMedia
import Foundation

public struct PlaybackDiagnostics: Sendable, Equatable {
    public var requestedRoute = PlaybackRoute.appleCompressed.rawValue
    public var selectedRoute = PlaybackRoute.appleCompressed.rawValue
    public var rendererInputKind = PlaybackRoute.appleCompressed.rendererInputKind.rawValue
    public var codecName = "unknown"
    public var currentSeconds = 0.0
    public var durationSeconds = 0.0
    public var nominalFrameRate = 0.0
    public var enqueuedSampleCount = 0
    public var timelineConfiguredBeforeFirstEnqueue: Bool?
    public var sourcePixelFormat = "----"
    public var destinationPixelFormat = "----"
    public var dimensions = "—"
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
    public var formatHasDvcC = false
    public var formatHasDvvC = false
    public var formatHasAmbientViewingEnvironment = false
    public var rendererStatus = "unknown"
    public var rendererError = "none"

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
        "\(selectedRoute)  •  \(timecode)  •  frame ≈ \(estimatedFrameNumber)  •  \(sourcePixelFormat) → \(destinationPixelFormat)  •  \(colorPrimaries) / \(transferFunction) / \(range)"
    }

    public var snapshotText: String {
        """
        requestedRoute: \(requestedRoute)
        selectedRoute: \(selectedRoute)
        rendererInput: \(rendererInputKind)
        codec: \(codecName)
        time: \(String(format: "%.6f", currentSeconds)) s / \(String(format: "%.6f", durationSeconds)) s
        estimatedFrame: \(estimatedFrameNumber) @ \(String(format: "%.3f", nominalFrameRate)) fps
        enqueuedSamples: \(enqueuedSampleCount)
        timelineConfiguredBeforeFirstEnqueue: \(timelineConfiguredBeforeFirstEnqueue.map(String.init) ?? "notObserved")
        pixelFormat: \(sourcePixelFormat) -> \(destinationPixelFormat)
        dimensions: \(dimensions)
        color: primaries=\(colorPrimaries), transfer=\(transferFunction), matrix=\(yCbCrMatrix), range=\(range)
        spatialFormat: projection=\(projectionKind), packing=\(viewPackingKind), leftEye=\(hasLeftStereoEyeView), rightEye=\(hasRightStereoEyeView)
        hdrMetadata.sourceBuffer: masteringDisplay=\(sourceBufferHasMasteringDisplayMetadata), contentLightLevel=\(sourceBufferHasContentLightLevelMetadata)
        hdrMetadata.trackFormat: masteringDisplay=\(trackFormatHasMasteringDisplayMetadata), contentLightLevel=\(trackFormatHasContentLightLevelMetadata)
        hdrMetadata.sourceFormat: masteringDisplay=\(sourceFormatHasMasteringDisplayMetadata), contentLightLevel=\(sourceFormatHasContentLightLevelMetadata)
        hdrMetadata.destinationBuffer: masteringDisplay=\(destinationBufferHasMasteringDisplayMetadata), contentLightLevel=\(destinationBufferHasContentLightLevelMetadata)
        compressedFormat: hvcC=\(formatHasHvcC), dvcC=\(formatHasDvcC), dvvC=\(formatHasDvvC), amve=\(formatHasAmbientViewingEnvironment)
        renderer: status=\(rendererStatus), error=\(rendererError)
        """
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
