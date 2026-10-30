@preconcurrency import AVFoundation
import Foundation
import OSLog
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
        let name = title
            ?? language.flatMap(PlaybackLanguageName.display)
            ?? "Track \(streamIndex)"
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
    private let sourceReadMeter: PlaybackSourceReadMeter
    private let demuxSession: FFmpegDemuxSession?

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil
    ) {
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
    }

    func allocate() -> FFmpegAudioReaderHandle? {
        PBFFmpegAudioReaderAllocate().map(FFmpegAudioReaderHandle.init(pointer:))
    }

    func open(
        _ reader: FFmpegAudioReaderHandle,
        source: String,
        startSeconds: Double,
        streamIndex: Int?
    ) throws -> AudioSampleProviderInfo {
        PBFFmpegAudioReaderSetSourceReadMonitor(
            reader.pointer,
            sourceReadMeter.bridgeMonitor
        )
        var error = [CChar](repeating: 0, count: 512)
        let opened = if let demuxSession {
            try demuxSession.withSource(argument: source) {
                PBFFmpegAudioReaderOpenWithDemuxSource(
                    reader.pointer,
                    $0,
                    Int32(streamIndex ?? -1),
                    startSeconds,
                    &error,
                    error.count
                )
            }
        } else {
            source.withCString { path in
                PBFFmpegAudioReaderOpen(
                    reader.pointer,
                    path,
                    startSeconds,
                    Int32(streamIndex ?? -1),
                    &error,
                    error.count
                )
            }
        }
        guard opened else {
            let message = ffmpegErrorMessage(error)
            if message == "The selected source has no audio stream" {
                throw AudioSampleProviderError.noAudioStream
            }
            throw AudioSampleProviderError.open(message)
        }
        return AudioSampleProviderInfo(
            providerKind: PBFFmpegAudioReaderOutputsPCM(reader.pointer)
                ? "FFmpegDecodedPCM"
                : "FFmpegCompressedAudio",
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
            let message = ffmpegErrorMessage(error)
            if let failure = PlaybackProviderError(
                bridgeCause: PBFFmpegAudioReaderGetLastActiveFailureCause(
                    reader.pointer
                ),
                message: message
            ) {
                throw failure
            }
            throw AudioSampleProviderError.read(message)
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

    func probeTracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack]
    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        description: PlaybackSourceDescription?
    ) async throws -> [PlaybackAudioTrack]
    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws
    func copyNextSample() async throws -> CMSampleBuffer?
    func cancel()
    func setPlaybackStartThreshold(_ seconds: Double?)
}

extension AudioSampleProvider {
    func setPlaybackStartThreshold(_ seconds: Double?) {}

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        description: PlaybackSourceDescription?
    ) async throws -> [PlaybackAudioTrack] {
        try await probeTracks(in: url, asset: asset)
    }
}

final class NoAudioSampleProvider: AudioSampleProvider {
    var info: AudioSampleProviderInfo? { nil }

    func probeTracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] { [] }

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
    func setPlaybackStartThreshold(_ seconds: Double?) {}
}

final class FFmpegAudioSampleProvider: AudioSampleProvider, @unchecked Sendable {
    private let logger = Logger(
        subsystem: "com.xiongzhipeng.PlaybackCore",
        category: "Playback"
    )
    var info: AudioSampleProviderInfo? {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private let demuxSession: FFmpegDemuxSession?
    private let readerQueue: DispatchQueue
    private let sourceReadMeter: PlaybackSourceReadMeter
    private let operations: any FFmpegAudioReaderOperations
    private let informationLoader: SystemMediaSourceInformationLoader
    private var storedInfo: AudioSampleProviderInfo?
    private let stallLock = NSLock()
    private var pendingReadStart: Date?
    private var lastStallReport: Date?
    private var stallMonitor: Task<Void, Never>?
    private var reader: FFmpegAudioReaderHandle?
    private var boundEpoch: UInt64?
    private var playbackStartThreshold: Double?
    private var generation: UInt64 = 0

    init(
        sourceReadMeter: PlaybackSourceReadMeter = PlaybackSourceReadMeter(),
        demuxSession: FFmpegDemuxSession? = nil,
        operations: (any FFmpegAudioReaderOperations)? = nil,
        readerQueue: DispatchQueue = DispatchQueue(
            label: "com.enchron.playbackcore.ffmpeg-audio-reader",
            qos: .userInitiated
        )
    ) {
        self.sourceReadMeter = sourceReadMeter
        self.demuxSession = demuxSession
        informationLoader = SystemMediaSourceInformationLoader(
            sourceReadMeter: sourceReadMeter,
            demuxSession: demuxSession
        )
        self.operations = operations
            ?? SystemFFmpegAudioReaderOperations(
                sourceReadMeter: sourceReadMeter,
                demuxSession: demuxSession
            )
        self.readerQueue = readerQueue
    }

    private func beginReadWatch() {
        stallLock.lock()
        pendingReadStart = Date()
        if stallMonitor == nil {
            stallMonitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self else { return }
                    self.reportReadStallIfNeeded()
                }
            }
        }
        stallLock.unlock()
    }

    private func endReadWatch() {
        stallLock.lock()
        pendingReadStart = nil
        stallMonitor?.cancel()
        stallMonitor = nil
        stallLock.unlock()
    }

    private func reportReadStallIfNeeded() {
        let now = Date()
        stallLock.lock()
        let started = pendingReadStart
        let lastReport = lastStallReport
        let shouldReport = started.map { now.timeIntervalSince($0) >= 2 } == true
            && (lastReport.map { now.timeIntervalSince($0) >= 2 } ?? true)
        if shouldReport { lastStallReport = now }
        stallLock.unlock()
        guard shouldReport, let started else { return }
        let info = self.info
        let streamIndex = info?.streamIndex ?? -1
        let queued = demuxSession?.queuedPacketCount(streamIndex: streamIndex) ?? -1
        let seconds = String(format: "%.1f", now.timeIntervalSince(started))
        let codec = info?.codecName ?? "unknown"
        let channels = info?.channelCount ?? 0
        let summary = "audio.read.stall seconds=\(seconds) codec=\(codec)"
            + " channels=\(channels) index=\(streamIndex) queued=\(queued)"
        logger.info("\(summary, privacy: .public)")
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
                        let epoch = demuxSession?.currentEpoch()
                        readerLock.withLock { boundEpoch = epoch }
                        let epochLabel = epoch.map(String.init) ?? "none"
                        logger.info("audio.reader.bind epoch=\(epochLabel, privacy: .public)")
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

    func setPlaybackStartThreshold(_ seconds: Double?) {
        readerLock.withLock { playbackStartThreshold = seconds }
        let label = seconds.map { String(format: "%.3f", $0) } ?? "none"
        logger.info("audio.read.threshold seconds=\(label, privacy: .public)")
    }

    func copyNextSample() async throws -> CMSampleBuffer? {
        var dropped = 0
        while true {
            guard let sample = try await readNextSampleOnce() else { return nil }
            let threshold = readerLock.withLock { playbackStartThreshold }
            guard let threshold else { return sample }
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration = CMSampleBufferGetDuration(sample).seconds
            let end = duration.isFinite ? start + duration : start
            if end <= threshold {
                dropped += 1
                continue
            }
            readerLock.withLock { playbackStartThreshold = nil }
            let summary = "audio.read.thresholdCleared dropped=\(dropped)"
                + " pts=\(String(format: "%.3f", start))"
            logger.info("\(summary, privacy: .public)")
            return sample
        }
    }

    private func readNextSampleOnce() async throws -> CMSampleBuffer? {
        let bound = readerLock.withLock { boundEpoch }
        if let bound, let current = demuxSession?.currentEpoch(), current != bound {
            let message = "source epoch moved from \(bound) to \(current)"
            logger.error("audio.read.staleEpoch \(message, privacy: .public)")
            throw AudioSampleProviderError.read(message)
        }
        guard let operation = readerLock.withLock({ reader.map { ($0, generation) } }) else {
            return nil
        }
        beginReadWatch()
        let outcome: FFmpegAudioReadOutcome = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                readerQueue.async { [self] in
                    guard isCurrent(operation.1, reader: operation.0) else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    defer { endReadWatch() }
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

    func probeTracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] {
        (try? await informationLoader.load(from: url))?.playbackAudioTracks ?? []
    }

    func tracks(
        in url: URL,
        asset: PlaybackAsset?,
        description: PlaybackSourceDescription?
    ) async throws -> [PlaybackAudioTrack] {
        if let description { return description.audioTracks }
        return try await probeTracks(in: url, asset: asset)
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
        "trueHDDecoderInputPacketCount": metadata.trueHDDecoderInputPacketCount,
        "trueHDDecoderBatchCount": metadata.trueHDDecoderBatchCount,
        "trueHDAggregatedDecoderBatchCount": metadata.trueHDAggregatedDecoderBatchCount,
        "trueHDOutputSampleBufferCount": metadata.trueHDOutputSampleBufferCount,
        "trueHDLastDecoderBatchInputPacketCount": metadata.trueHDLastDecoderBatchInputPacketCount
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
