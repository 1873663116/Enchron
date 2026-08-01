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

struct SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

struct FFmpegVideoReaderHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}

enum FFmpegVideoReadOutcome: @unchecked Sendable {
    case sample(SendableSampleBuffer)
    case end
    case cancelled
}

protocol FFmpegVideoReaderOperations: Sendable {
    func allocate() -> FFmpegVideoReaderHandle?
    func open(
        _ reader: FFmpegVideoReaderHandle,
        source: String,
        startSeconds: Double
    ) throws -> VideoSampleProviderInfo
    func copyNextSample(from reader: FFmpegVideoReaderHandle) throws -> FFmpegVideoReadOutcome
    func cancel(_ reader: FFmpegVideoReaderHandle)
    func destroy(_ reader: FFmpegVideoReaderHandle)
}

struct SystemFFmpegVideoReaderOperations: FFmpegVideoReaderOperations {
    func allocate() -> FFmpegVideoReaderHandle? {
        PBFFmpegReaderAllocate().map(FFmpegVideoReaderHandle.init(pointer:))
    }

    func open(
        _ reader: FFmpegVideoReaderHandle,
        source: String,
        startSeconds: Double
    ) throws -> VideoSampleProviderInfo {
        var error = [CChar](repeating: 0, count: 512)
        let opened = source.withCString { path in
            PBFFmpegReaderOpen(
                reader.pointer,
                path,
                PBFFmpegModeCompressed,
                startSeconds,
                &error,
                error.count
            )
        }
        guard opened else {
            throw PlaybackProviderError.ffmpeg(ffmpegErrorMessage(error))
        }
        let configurationAtoms = [
            PBFFmpegReaderFormatHasHvcC(reader.pointer) ? "hvcC" : nil,
            PBFFmpegReaderFormatHasDvcC(reader.pointer) ? "dvcC" : nil,
            PBFFmpegReaderFormatHasDvvC(reader.pointer) ? "dvvC" : nil,
        ].compactMap(\.self)
        return VideoSampleProviderInfo(
            providerKind: "FFmpegCompressed",
            containerFormat: String(cString: PBFFmpegReaderGetContainerFormat(reader.pointer)),
            durationSeconds: PBFFmpegReaderGetDurationSeconds(reader.pointer),
            nominalFrameRate: PBFFmpegReaderGetNominalFrameRate(reader.pointer),
            codecName: String(cString: PBFFmpegReaderGetCodecName(reader.pointer)),
            codecTag: String(cString: PBFFmpegReaderGetCodecTag(reader.pointer)),
            dimensions: "\(PBFFmpegReaderGetWidth(reader.pointer))x\(PBFFmpegReaderGetHeight(reader.pointer))",
            colorPrimaries: String(cString: PBFFmpegReaderGetColorPrimaries(reader.pointer)),
            transferFunction: String(cString: PBFFmpegReaderGetTransferFunction(reader.pointer)),
            yCbCrMatrix: String(cString: PBFFmpegReaderGetYCbCrMatrix(reader.pointer)),
            range: String(cString: PBFFmpegReaderGetColorRange(reader.pointer)),
            seekability: .init(known: "providerRebuild"),
            selectedRawTrackMapping: .init(
                known: "stream:\(PBFFmpegReaderGetVideoStreamIndex(reader.pointer))"
            ),
            timebase: .init(
                known: "\(PBFFmpegReaderGetTimeBaseNumerator(reader.pointer))/\(PBFFmpegReaderGetTimeBaseDenominator(reader.pointer))"
            ),
            codecConfigurationSummary: configurationAtoms.isEmpty
                ? .init(.none)
                : .init(known: configurationAtoms.joined(separator: ",")),
            formatSignaling: VideoFormatSignalingSummary(
                provenance: "FFmpeg.codecParameters",
                colorPrimaries: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorPrimaries(reader.pointer))
                ),
                transferFunction: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetTransferFunction(reader.pointer))
                ),
                yCbCrMatrix: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetYCbCrMatrix(reader.pointer))
                ),
                range: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetColorRange(reader.pointer))
                ),
                projectionKind: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetProjectionKind(reader.pointer))
                ),
                viewPackingKind: ffmpegStringFact(
                    String(cString: PBFFmpegReaderGetViewPackingKind(reader.pointer))
                ),
                hvcC: PBFFmpegReaderFormatHasHvcC(reader.pointer)
                    ? .init(known: true)
                    : .init(.none),
                dvcC: PBFFmpegReaderFormatHasDvcC(reader.pointer)
                    ? .init(known: true)
                    : .init(.none),
                dvvC: PBFFmpegReaderFormatHasDvvC(reader.pointer)
                    ? .init(known: true)
                    : .init(.none)
            )
        )
    }

    func copyNextSample(from reader: FFmpegVideoReaderHandle) throws -> FFmpegVideoReadOutcome {
        var sample: Unmanaged<CMSampleBuffer>?
        var error = [CChar](repeating: 0, count: 512)
        let result = PBFFmpegReaderCopyNextSample(
            reader.pointer,
            &sample,
            &error,
            error.count
        )
        switch result {
        case PBFFmpegReadResultSample:
            guard let sample else { return .end }
            return .sample(SendableSampleBuffer(value: sample.takeRetainedValue()))
        case PBFFmpegReadResultEnd:
            return .end
        case PBFFmpegReadResultCancelled:
            return .cancelled
        default:
            throw PlaybackProviderError.ffmpeg(ffmpegErrorMessage(error))
        }
    }

    func cancel(_ reader: FFmpegVideoReaderHandle) {
        PBFFmpegReaderCancel(reader.pointer)
    }

    func destroy(_ reader: FFmpegVideoReaderHandle) {
        PBFFmpegReaderDestroy(reader.pointer)
    }

    private func ffmpegStringFact(_ value: String) -> ObservedStringFact {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "unknown", normalized != "unspecified" else {
            return .init(.unknown)
        }
        return .init(known: value)
    }
}

final class FFmpegSampleProvider: VideoSampleProvider, @unchecked Sendable {
    var info: VideoSampleProviderInfo {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private let readerQueue: DispatchQueue
    private let operations: any FFmpegVideoReaderOperations
    private var storedInfo = VideoSampleProviderInfo()
    private var reader: FFmpegVideoReaderHandle?
    private var generation: UInt64 = 0

    init(
        operations: any FFmpegVideoReaderOperations = SystemFFmpegVideoReaderOperations(),
        readerQueue: DispatchQueue = DispatchQueue(
            label: "com.enchron.playbackcore.ffmpeg-video-reader"
        )
    ) {
        self.operations = operations
        self.readerQueue = readerQueue
    }

    func prepare(url: URL, asset: PlaybackAsset?, startTime: CMTime) async throws {
        cancel()
        let operationGeneration = readerLock.withLock { generation }
        let source = FFmpegSourceLocator.argument(for: url)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                readerQueue.async { [self] in
                    guard isCurrent(operationGeneration) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    guard let newReader = operations.allocate() else {
                        guard isCurrent(operationGeneration) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(
                            throwing: PlaybackProviderError.ffmpeg(
                                "Unable to allocate FFmpeg reader"
                            )
                        )
                        return
                    }
                    guard install(newReader, for: operationGeneration) else {
                        operations.destroy(newReader)
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        let newInfo = try operations.open(
                            newReader,
                            source: source,
                            startSeconds: startTime.seconds
                        )
                        guard accept(newInfo, from: newReader, generation: operationGeneration) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume()
                    } catch {
                        guard removeIfCurrent(newReader, generation: operationGeneration) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        operations.destroy(newReader)
                        continuation.resume(throwing: error)
                    }
                }
            }
            try Task.checkCancellation()
        } onCancel: { [weak self] in
            self?.cancel(generation: operationGeneration)
        }
    }

    func start() throws {}

    func nextEvent() async throws -> VideoSampleProviderEvent {
        guard let operation = readerLock.withLock({ reader.map { ($0, generation) } }) else {
            return .end
        }
        let outcome: FFmpegVideoReadOutcome = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                readerQueue.async { [self] in
                    guard isCurrent(operation.1, reader: operation.0) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        let outcome = try operations.copyNextSample(from: operation.0)
                        guard isCurrent(operation.1, reader: operation.0) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        if case .cancelled = outcome {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: outcome)
                        }
                    } catch {
                        guard isCurrent(operation.1, reader: operation.0) else {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            self?.cancel(generation: operation.1)
        }
        switch outcome {
        case .sample(let sample): return .sample(sample.value)
        case .end: return .end
        case .cancelled: throw CancellationError()
        }
    }

    func cancel() {
        cancel(generation: nil)
    }

    deinit {
        cancel()
    }

    private func cancel(generation expectedGeneration: UInt64?) {
        let cancelledReader: FFmpegVideoReaderHandle? = readerLock.withLock {
            if let expectedGeneration, generation != expectedGeneration { return nil }
            generation &+= 1
            let cancelledReader = reader
            reader = nil
            storedInfo = VideoSampleProviderInfo()
            return cancelledReader
        }
        guard let cancelledReader else { return }
        operations.cancel(cancelledReader)
        readerQueue.async { [operations] in
            operations.destroy(cancelledReader)
        }
    }

    private func isCurrent(
        _ expectedGeneration: UInt64,
        reader expectedReader: FFmpegVideoReaderHandle? = nil
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration else { return false }
            guard let expectedReader else { return true }
            return reader?.pointer == expectedReader.pointer
        }
    }

    private func install(
        _ newReader: FFmpegVideoReaderHandle,
        for expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration, reader == nil else { return false }
            reader = newReader
            return true
        }
    }

    private func accept(
        _ newInfo: VideoSampleProviderInfo,
        from openedReader: FFmpegVideoReaderHandle,
        generation expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration,
                  reader?.pointer == openedReader.pointer else { return false }
            storedInfo = newInfo
            return true
        }
    }

    private func removeIfCurrent(
        _ failedReader: FFmpegVideoReaderHandle,
        generation expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration,
                  reader?.pointer == failedReader.pointer else { return false }
            reader = nil
            return true
        }
    }
}

func ffmpegErrorMessage(_ buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
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
