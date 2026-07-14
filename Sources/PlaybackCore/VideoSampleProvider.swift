@preconcurrency import AVFoundation
import Foundation
import PlaybackFFmpegBridge

struct VideoSampleProviderInfo: Sendable {
    var providerKind = "unknown"
    var containerFormat = "unknown"
    var durationSeconds = 0.0
    var nominalFrameRate = 0.0
    var codecName = "unknown"
    var codecTag = "unknown"
    var dimensions = "unknown"
    var colorPrimaries = "unknown"
    var transferFunction = "unknown"
    var yCbCrMatrix = "unknown"
    var range = "unknown"
    var seekability = ObservedStringFact(.unknown)
    var selectedRawTrackMapping = ObservedStringFact(.notExposed)
    var timebase = ObservedStringFact(.notExposed)
    var codecConfigurationSummary = ObservedStringFact(.notExposed)
    var formatSignaling = VideoFormatSignalingSummary(provenance: "providerOpen")
    var trackFormatHasMasteringDisplayMetadata = false
    var trackFormatHasContentLightLevelMetadata = false
}

protocol VideoSampleProvider: AnyObject {
    var route: PlaybackRoute { get }
    var info: VideoSampleProviderInfo { get }

    func prepare(url: URL, startTime: CMTime) async throws
    func start() throws
    func copyNextEvent() throws -> VideoSampleProviderEvent
    func cancel()
}

enum VideoSampleProviderEvent {
    case sample(CMSampleBuffer)
    case formatChanged
    case flush
    case end
}

final class AppleCompressedSampleProvider: VideoSampleProvider {
    let route = PlaybackRoute.appleCompressed
    private(set) var info = VideoSampleProviderInfo()

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?

    func prepare(url: URL, startTime: CMTime) async throws {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetShouldParseExternalSphericalTagsKey: true]
        )
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PlaybackProviderError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let naturalTimeScale = try await track.load(.naturalTimeScale)
        let formatDescriptions = try await track.load(.formatDescriptions)
        let formatExtensions = formatDescriptions
            .map { CMFormatDescriptionGetExtensions($0) as? [String: Any] ?? [:] }
        let firstFormat = formatDescriptions.first
        let firstExtensions = formatExtensions.first ?? [:]
        let projectionWasSynthesizedFromExternalTags =
            firstExtensions[
                kCMFormatDescriptionExtension_ConvertedFromExternalSphericalTags as String
            ] as? Bool == true
        let firstAtoms = firstExtensions[
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String
        ] as? [String: Any] ?? [:]
        let dimensions = firstFormat.map(CMVideoFormatDescriptionGetDimensions)
        let configurationAtoms = ["hvcC", "dvcC", "dvvC", "amve"].filter {
            firstAtoms[$0] != nil
        }
        info = VideoSampleProviderInfo(
            providerKind: "AVAssetReaderTrackOutput",
            containerFormat: url.pathExtension.lowercased(),
            durationSeconds: duration.seconds,
            nominalFrameRate: Double(try await track.load(.nominalFrameRate)),
            codecName: firstFormat.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown",
            codecTag: firstFormat.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown",
            dimensions: dimensions.map { "\($0.width)x\($0.height)" } ?? "unknown",
            colorPrimaries: Self.extensionString(firstExtensions, key: kCMFormatDescriptionExtension_ColorPrimaries),
            transferFunction: Self.extensionString(firstExtensions, key: kCMFormatDescriptionExtension_TransferFunction),
            yCbCrMatrix: Self.extensionString(firstExtensions, key: kCMFormatDescriptionExtension_YCbCrMatrix),
            range: Self.rangeString(firstExtensions),
            seekability: .init(.known, value: "providerRebuild"),
            selectedRawTrackMapping: .init(.known, value: "primaryVideo"),
            timebase: .init(.known, value: "1/\(naturalTimeScale)"),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(.known, value: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: projectionWasSynthesizedFromExternalTags
                    ? "AVAssetTrack.formatDescription.externalSphericalTagsSynthesis"
                    : "AVAssetTrack.formatDescription",
                colorPrimaries: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_ColorPrimaries
                ),
                transferFunction: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_TransferFunction
                ),
                yCbCrMatrix: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_YCbCrMatrix
                ),
                range: Self.rangeFact(firstExtensions),
                projectionKind: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_ProjectionKind
                ),
                viewPackingKind: Self.stringFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_ViewPackingKind
                ),
                hasLeftStereoEyeView: Self.booleanFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_HasLeftStereoEyeView
                ),
                hasRightStereoEyeView: Self.booleanFact(
                    firstExtensions,
                    key: kCMFormatDescriptionExtension_HasRightStereoEyeView
                ),
                masteringDisplayMetadata: Self.presenceFact(
                    firstExtensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String]
                ),
                contentLightLevelMetadata: Self.presenceFact(
                    firstExtensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String]
                ),
                hvcC: Self.presenceFact(firstAtoms["hvcC"]),
                dvcC: Self.presenceFact(firstAtoms["dvcC"]),
                dvvC: Self.presenceFact(firstAtoms["dvvC"]),
                ambientViewingEnvironment: Self.presenceFact(
                    firstExtensions[kCMFormatDescriptionExtension_AmbientViewingEnvironment as String]
                        ?? firstAtoms["amve"]
                )
            ),
            trackFormatHasMasteringDisplayMetadata: formatExtensions.contains {
                $0[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] != nil
            },
            trackFormatHasContentLightLevelMetadata: formatExtensions.contains {
                $0[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] != nil
            }
        )

        let reader = try AVAssetReader(asset: asset)
        if startTime > .zero {
            reader.timeRange = CMTimeRange(start: startTime, end: duration)
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw PlaybackProviderError.cannotAddReaderOutput
        }
        reader.add(output)
        self.reader = reader
        self.output = output
    }

    func start() throws {
        guard let reader, reader.startReading() else {
            throw reader?.error ?? PlaybackProviderError.readerDidNotStart
        }
    }

    func copyNextEvent() throws -> VideoSampleProviderEvent {
        if let sample = output?.copyNextSampleBuffer() {
            return .sample(sample)
        }
        if reader?.status == .failed {
            throw reader?.error ?? PlaybackProviderError.readerFailed
        }
        return .end
    }

    func cancel() {
        reader?.cancelReading()
        reader = nil
        output = nil
    }

    private static func extensionString(_ extensions: [String: Any], key: CFString) -> String {
        extensions[key as String].map { String(describing: $0) } ?? "unknown"
    }

    private static func stringFact(
        _ extensions: [String: Any],
        key: CFString
    ) -> ObservedStringFact {
        guard let value = extensions[key as String] else { return .init(.none) }
        return .init(.known, value: String(describing: value))
    }

    private static func presenceFact(_ value: Any?) -> ObservedBooleanFact {
        value == nil ? .init(.none, value: false) : .init(.known, value: true)
    }

    private static func booleanFact(
        _ extensions: [String: Any],
        key: CFString
    ) -> ObservedBooleanFact {
        guard let value = extensions[key as String] as? Bool else {
            return .init(.none)
        }
        return .init(.known, value: value)
    }

    private static func rangeString(_ extensions: [String: Any]) -> String {
        guard let fullRange = extensions[
            kCMFormatDescriptionExtension_FullRangeVideo as String
        ] as? Bool else { return "unknown" }
        return fullRange ? "full" : "video"
    }

    private static func rangeFact(_ extensions: [String: Any]) -> ObservedStringFact {
        let value = rangeString(extensions)
        return value == "unknown" ? .init(.unknown) : .init(.known, value: value)
    }
}

final class FFmpegSampleProvider: VideoSampleProvider {
    let route: PlaybackRoute
    private(set) var info = VideoSampleProviderInfo()

    private var reader: OpaquePointer?

    init(route: PlaybackRoute) {
        precondition(route == .ffmpegCompressed)
        self.route = route
    }

    func prepare(url: URL, startTime: CMTime) async throws {
        var error = [CChar](repeating: 0, count: 512)
        reader = url.path.withCString { path in
            PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, startTime.seconds, &error, error.count)
        }
        guard let reader else {
            throw PlaybackProviderError.ffmpeg(Self.errorMessage(error))
        }
        let configurationAtoms = [
            PBFFmpegReaderFormatHasHvcC(reader) ? "hvcC" : nil,
            PBFFmpegReaderFormatHasDvcC(reader) ? "dvcC" : nil,
            PBFFmpegReaderFormatHasDvvC(reader) ? "dvvC" : nil,
        ].compactMap(\.self)
        info = VideoSampleProviderInfo(
            providerKind: "FFmpegCompressed",
            containerFormat: String(cString: PBFFmpegReaderGetContainerFormat(reader)),
            durationSeconds: PBFFmpegReaderGetDurationSeconds(reader),
            nominalFrameRate: PBFFmpegReaderGetNominalFrameRate(reader),
            codecName: String(cString: PBFFmpegReaderGetCodecName(reader)),
            codecTag: String(cString: PBFFmpegReaderGetCodecTag(reader)),
            dimensions: "\(PBFFmpegReaderGetWidth(reader))x\(PBFFmpegReaderGetHeight(reader))",
            colorPrimaries: String(cString: PBFFmpegReaderGetColorPrimaries(reader)),
            transferFunction: String(cString: PBFFmpegReaderGetTransferFunction(reader)),
            yCbCrMatrix: String(cString: PBFFmpegReaderGetYCbCrMatrix(reader)),
            range: String(cString: PBFFmpegReaderGetColorRange(reader)),
            seekability: .init(.known, value: "providerRebuild"),
            selectedRawTrackMapping: .init(
                .known,
                value: "stream:\(PBFFmpegReaderGetVideoStreamIndex(reader))"
            ),
            timebase: .init(
                .known,
                value: "\(PBFFmpegReaderGetTimeBaseNumerator(reader))/\(PBFFmpegReaderGetTimeBaseDenominator(reader))"
            ),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(.known, value: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                colorPrimaries: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorPrimaries(reader))
                ),
                transferFunction: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetTransferFunction(reader))
                ),
                yCbCrMatrix: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetYCbCrMatrix(reader))
                ),
                range: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorRange(reader))
                ),
                projectionKind: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetProjectionKind(reader))
                ),
                viewPackingKind: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetViewPackingKind(reader))
                ),
                hvcC: PBFFmpegReaderFormatHasHvcC(reader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false),
                dvcC: PBFFmpegReaderFormatHasDvcC(reader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false),
                dvvC: PBFFmpegReaderFormatHasDvvC(reader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false)
            )
        )
    }

    func start() throws {}

    func copyNextEvent() throws -> VideoSampleProviderEvent {
        guard let reader else { return .end }
        var sample: Unmanaged<CMSampleBuffer>?
        var error = [CChar](repeating: 0, count: 512)
        let result = PBFFmpegReaderCopyNextSample(reader, &sample, &error, error.count)
        switch result {
        case PBFFmpegReadResultSample:
            guard let sample else { return .end }
            return .sample(sample.takeRetainedValue())
        case PBFFmpegReadResultEnd:
            return .end
        default:
            throw PlaybackProviderError.ffmpeg(Self.errorMessage(error))
        }
    }

    func cancel() {
        if let reader {
            PBFFmpegReaderDestroy(reader)
            self.reader = nil
        }
    }

    deinit {
        cancel()
    }

    private static func errorMessage(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func ffmpegStringFact(_ value: String) -> ObservedStringFact {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "unknown", normalized != "unspecified" else {
            return .init(.unknown)
        }
        return .init(.known, value: value)
    }
}

enum PlaybackProviderError: LocalizedError {
    case noVideoTrack
    case cannotAddReaderOutput
    case readerDidNotStart
    case readerFailed
    case ffmpeg(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The selected file has no video track."
        case .cannotAddReaderOutput: "AVAssetReader rejected the storage-format video output."
        case .readerDidNotStart: "AVAssetReader could not start reading."
        case .readerFailed: "AVAssetReader failed while reading samples."
        case .ffmpeg(let message): "FFmpeg: \(message)"
        }
    }
}
