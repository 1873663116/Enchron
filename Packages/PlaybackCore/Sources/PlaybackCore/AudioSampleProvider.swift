@preconcurrency import AVFoundation
import Foundation
import PlaybackFFmpegBridge

public struct PlaybackAudioTrack: Identifiable, Sendable, Equatable, Codable {
    public let streamIndex: Int
    public let codecName: String
    public let sampleRate: Int
    public let channelCount: Int
    public let language: String?
    public let title: String?

    public var id: Int { streamIndex }
    public var label: String {
        let name = title ?? language ?? "Track \(streamIndex)"
        return "\(name) · \(codecName) · \(channelCount)ch"
    }
}

struct AudioSampleProviderInfo: Sendable, Equatable {
    var providerKind: String
    var streamIndex: Int
    var codecName: String
    var sampleRate: Int
    var channelCount: Int
}

struct SendableAudioSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
}

struct FFmpegAudioReaderHandle: @unchecked Sendable {
    let pointer: OpaquePointer
}

enum FFmpegAudioReadOutcome: @unchecked Sendable {
    case sample(SendableAudioSampleBuffer)
    case end
    case cancelled
}

protocol FFmpegAudioReaderOperations: Sendable {
    func allocate() -> FFmpegAudioReaderHandle?
    func open(
        _ reader: FFmpegAudioReaderHandle,
        source: String,
        startSeconds: Double,
        streamIndex: Int?
    ) throws -> AudioSampleProviderInfo
    func copyNextSample(from reader: FFmpegAudioReaderHandle) throws -> FFmpegAudioReadOutcome
    func cancel(_ reader: FFmpegAudioReaderHandle)
    func destroy(_ reader: FFmpegAudioReaderHandle)
}

struct SystemFFmpegAudioReaderOperations: FFmpegAudioReaderOperations {
    func allocate() -> FFmpegAudioReaderHandle? {
        PBFFmpegAudioReaderAllocate().map(FFmpegAudioReaderHandle.init(pointer:))
    }

    func open(
        _ reader: FFmpegAudioReaderHandle,
        source: String,
        startSeconds: Double,
        streamIndex: Int?
    ) throws -> AudioSampleProviderInfo {
        var error = [CChar](repeating: 0, count: 512)
        let opened = source.withCString { path in
            PBFFmpegAudioReaderOpen(
                reader.pointer,
                path,
                startSeconds,
                Int32(streamIndex ?? -1),
                &error,
                error.count
            )
        }
        guard opened else {
            let message = ffmpegErrorMessage(error)
            if message == "The selected source has no audio stream" {
                throw AudioSampleProviderError.noAudioStream
            }
            throw AudioSampleProviderError.open(message)
        }
        return AudioSampleProviderInfo(
            providerKind: "FFmpegCompressedAudio",
            streamIndex: Int(PBFFmpegAudioReaderGetStreamIndex(reader.pointer)),
            codecName: String(cString: PBFFmpegAudioReaderGetCodecName(reader.pointer)),
            sampleRate: Int(PBFFmpegAudioReaderGetSampleRate(reader.pointer)),
            channelCount: Int(PBFFmpegAudioReaderGetChannelCount(reader.pointer))
        )
    }

    func copyNextSample(from reader: FFmpegAudioReaderHandle) throws -> FFmpegAudioReadOutcome {
        var sample: Unmanaged<CMSampleBuffer>?
        var metadata = PBFFmpegAudioSampleMetadata()
        var error = [CChar](repeating: 0, count: 512)
        let result = PBFFmpegAudioReaderCopyNextSample(
            reader.pointer,
            &sample,
            &metadata,
            &error,
            error.count
        )
        switch result {
        case PBFFmpegReadResultSample:
            guard let sample = sample?.takeRetainedValue() else { return .end }
            attachFFmpegAudioDiagnosticMetadata(metadata, to: sample)
            return .sample(SendableAudioSampleBuffer(value: sample))
        case PBFFmpegReadResultEnd:
            return .end
        case PBFFmpegReadResultCancelled:
            return .cancelled
        default:
            throw AudioSampleProviderError.read(ffmpegErrorMessage(error))
        }
    }

    func cancel(_ reader: FFmpegAudioReaderHandle) {
        PBFFmpegAudioReaderCancel(reader.pointer)
    }

    func destroy(_ reader: FFmpegAudioReaderHandle) {
        PBFFmpegAudioReaderDestroy(reader.pointer)
    }
}

protocol AudioSampleProvider: AnyObject {
    var info: AudioSampleProviderInfo? { get }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack]
    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws
    func copyNextSample() async throws -> CMSampleBuffer?
    func cancel()
}

final class NoAudioSampleProvider: AudioSampleProvider {
    var info: AudioSampleProviderInfo? { nil }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] { [] }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws {
        throw AudioSampleProviderError.noAudioStream
    }

    func copyNextSample() async throws -> CMSampleBuffer? { nil }
    func cancel() {}
}

final class FFmpegCompressedAudioSampleProvider: AudioSampleProvider, @unchecked Sendable {
    var info: AudioSampleProviderInfo? {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private let readerQueue: DispatchQueue
    private let operations: any FFmpegAudioReaderOperations
    private var storedInfo: AudioSampleProviderInfo?
    private var reader: FFmpegAudioReaderHandle?
    private var generation: UInt64 = 0

    init(
        operations: any FFmpegAudioReaderOperations = SystemFFmpegAudioReaderOperations(),
        readerQueue: DispatchQueue = DispatchQueue(
            label: "com.enchron.playbackcore.ffmpeg-audio-reader"
        )
    ) {
        self.operations = operations
        self.readerQueue = readerQueue
    }

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws {
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
                            throwing: AudioSampleProviderError.open(
                                "Unable to allocate FFmpeg audio reader"
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
                            startSeconds: startTime.seconds,
                            streamIndex: streamIndex
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

    func copyNextSample() async throws -> CMSampleBuffer? {
        guard let operation = readerLock.withLock({ reader.map { ($0, generation) } }) else {
            return nil
        }
        let outcome: FFmpegAudioReadOutcome = try await withTaskCancellationHandler {
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
        case .sample(let sample): return sample.value
        case .end: return nil
        case .cancelled: throw CancellationError()
        }
    }

    func cancel() {
        cancel(generation: nil)
    }

    deinit {
        cancel()
    }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] {
        let source = FFmpegSourceLocator.argument(for: url)
        return await withCheckedContinuation { continuation in
            readerQueue.async {
                continuation.resume(returning: source.withCString { path in
                    let count = max(0, Int(PBFFmpegAudioTrackCount(path)))
                    return (0..<count).compactMap { ordinal in
                        var streamIndex: Int32 = -1
                        var sampleRate: Int32 = 0
                        var channelCount: Int32 = 0
                        var codec = [CChar](repeating: 0, count: 64)
                        var language = [CChar](repeating: 0, count: 64)
                        var title = [CChar](repeating: 0, count: 256)
                        guard PBFFmpegAudioTrackCopyInfo(
                            path, Int32(ordinal), &streamIndex, &sampleRate, &channelCount,
                            &codec, codec.count, &language, language.count, &title, title.count
                        ) else { return nil }
                        func string(_ buffer: [CChar]) -> String? {
                            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                            let value = String(decoding: bytes, as: UTF8.self)
                            return value.isEmpty ? nil : value
                        }
                        return PlaybackAudioTrack(
                            streamIndex: Int(streamIndex), codecName: string(codec) ?? "unknown",
                            sampleRate: Int(sampleRate), channelCount: Int(channelCount),
                            language: string(language), title: string(title)
                        )
                    }
                })
            }
        }
    }

    private func cancel(generation expectedGeneration: UInt64?) {
        let cancelledReader: FFmpegAudioReaderHandle? = readerLock.withLock {
            if let expectedGeneration, generation != expectedGeneration { return nil }
            generation &+= 1
            let cancelledReader = reader
            reader = nil
            storedInfo = nil
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
        reader expectedReader: FFmpegAudioReaderHandle? = nil
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration else { return false }
            guard let expectedReader else { return true }
            return reader?.pointer == expectedReader.pointer
        }
    }

    private func install(
        _ newReader: FFmpegAudioReaderHandle,
        for expectedGeneration: UInt64
    ) -> Bool {
        readerLock.withLock {
            guard generation == expectedGeneration, reader == nil else { return false }
            reader = newReader
            return true
        }
    }

    private func accept(
        _ newInfo: AudioSampleProviderInfo,
        from openedReader: FFmpegAudioReaderHandle,
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
        _ failedReader: FFmpegAudioReaderHandle,
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

private func attachFFmpegAudioDiagnosticMetadata(
    _ metadata: PBFFmpegAudioSampleMetadata,
    to sample: CMSampleBuffer
) {
    let values: [String: Any] = [
        "packetPTS": metadata.packetPTS,
        "packetDTS": metadata.packetDTS,
        "packetDuration": metadata.packetDuration,
        "timeBaseNumerator": metadata.timeBaseNumerator,
        "timeBaseDenominator": metadata.timeBaseDenominator,
        "payloadByteCount": metadata.payloadByteCount,
        "cookieSource": ffmpegAudioCookieSourceLabel(metadata.cookieSource),
    ]
    CMSetAttachment(
        sample,
        key: "com.enchron.playbackcore.ffmpegAudioMetadata" as CFString,
        value: values as CFDictionary,
        attachmentMode: kCMAttachmentMode_ShouldNotPropagate
    )
}

private func ffmpegAudioCookieSourceLabel(_ source: PBFFmpegAudioCookieSource) -> String {
    switch source {
    case PBFFmpegAudioCookieSourceExtradata: "extradata"
    case PBFFmpegAudioCookieSourceSynthesized: "synthesized"
    case PBFFmpegAudioCookieSourceFilterOutput: "filterOutput"
    default: "unavailable"
    }
}

enum AudioSampleProviderError: LocalizedError {
    case noAudioStream
    case open(String)
    case read(String)

    var errorDescription: String? {
        switch self {
        case .noAudioStream: "The selected source has no audio stream"
        case .open(let message): "Audio open failed: \(message)"
        case .read(let message): "Audio read failed: \(message)"
        }
    }
}
