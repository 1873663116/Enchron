@preconcurrency import AVFoundation
import Foundation
import PlaybackFFmpegBridge

enum FFmpegSourceLocator {
    static func argument(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }
}

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
    var info: VideoSampleProviderInfo { get }

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws
    func start() throws
    func nextEvent() async throws -> VideoSampleProviderEvent
    func cancel()
}

enum VideoSampleProviderEvent {
    case sample(CMSampleBuffer)
    case formatChanged
    case flush
    case end
}

private struct SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

final class FFmpegSampleProvider: VideoSampleProvider {
    var info: VideoSampleProviderInfo {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private var storedInfo = VideoSampleProviderInfo()
    private var reader: OpaquePointer?

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {
        var error = [CChar](repeating: 0, count: 512)
        let newReader = FFmpegSourceLocator.argument(for: url).withCString { path in
            PBFFmpegReaderCreate(path, PBFFmpegModeCompressed, startTime.seconds, &error, error.count)
        }
        guard let newReader else {
            throw PlaybackProviderError.ffmpeg(Self.errorMessage(error))
        }
        let configurationAtoms = [
            PBFFmpegReaderFormatHasHvcC(newReader) ? "hvcC" : nil,
            PBFFmpegReaderFormatHasDvcC(newReader) ? "dvcC" : nil,
            PBFFmpegReaderFormatHasDvvC(newReader) ? "dvvC" : nil,
        ].compactMap(\.self)
        let newInfo = VideoSampleProviderInfo(
            providerKind: "FFmpegCompressed",
            containerFormat: String(cString: PBFFmpegReaderGetContainerFormat(newReader)),
            durationSeconds: PBFFmpegReaderGetDurationSeconds(newReader),
            nominalFrameRate: PBFFmpegReaderGetNominalFrameRate(newReader),
            codecName: String(cString: PBFFmpegReaderGetCodecName(newReader)),
            codecTag: String(cString: PBFFmpegReaderGetCodecTag(newReader)),
            dimensions: "\(PBFFmpegReaderGetWidth(newReader))x\(PBFFmpegReaderGetHeight(newReader))",
            colorPrimaries: String(cString: PBFFmpegReaderGetColorPrimaries(newReader)),
            transferFunction: String(cString: PBFFmpegReaderGetTransferFunction(newReader)),
            yCbCrMatrix: String(cString: PBFFmpegReaderGetYCbCrMatrix(newReader)),
            range: String(cString: PBFFmpegReaderGetColorRange(newReader)),
            seekability: .init(.known, value: "providerRebuild"),
            selectedRawTrackMapping: .init(
                .known,
                value: "stream:\(PBFFmpegReaderGetVideoStreamIndex(newReader))"
            ),
            timebase: .init(
                .known,
                value: "\(PBFFmpegReaderGetTimeBaseNumerator(newReader))/\(PBFFmpegReaderGetTimeBaseDenominator(newReader))"
            ),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(.known, value: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                colorPrimaries: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorPrimaries(newReader))
                ),
                transferFunction: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetTransferFunction(newReader))
                ),
                yCbCrMatrix: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetYCbCrMatrix(newReader))
                ),
                range: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorRange(newReader))
                ),
                projectionKind: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetProjectionKind(newReader))
                ),
                viewPackingKind: Self.ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetViewPackingKind(newReader))
                ),
                hvcC: PBFFmpegReaderFormatHasHvcC(newReader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false),
                dvcC: PBFFmpegReaderFormatHasDvcC(newReader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false),
                dvvC: PBFFmpegReaderFormatHasDvvC(newReader)
                    ? .init(.known, value: true)
                    : .init(.none, value: false)
            )
        )
        readerLock.withLock {
            if let reader { PBFFmpegReaderDestroy(reader) }
            reader = newReader
            storedInfo = newInfo
        }
    }

    func start() throws {}

    func nextEvent() async throws -> VideoSampleProviderEvent {
        try readerLock.withLock {
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
    }

    func cancel() {
        readerLock.withLock {
            if let reader {
                PBFFmpegReaderDestroy(reader)
                self.reader = nil
            }
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
    case readerDidNotStart
    case readerFailed(String)
    case ffmpeg(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The selected file has no video track."
        case .readerDidNotStart: "AVAssetReader could not start reading."
        case .readerFailed(let message): "AVAssetReader failed: \(message)"
        case .ffmpeg(let message): "FFmpeg: \(message)"
        }
    }
}
