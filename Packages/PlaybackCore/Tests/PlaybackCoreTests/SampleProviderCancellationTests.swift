import AVFoundation
import Foundation
import Testing
@testable import PlaybackCore

@Test func videoReadCancellationDiscardsStaleResultAndDestroysAfterReadExit() async throws {
    let operations = BlockingVideoReaderOperations(resultAfterCancellation: .end)
    let provider = FFmpegSampleProvider(operations: operations)
    try await provider.prepare(
        url: URL(fileURLWithPath: "/fixtures/blocking-video.mkv"),
        asset: nil,
        startTime: .zero
    )

    let read = Task { await videoReadVerdict(from: provider) }
    await operations.readEntered.wait()

    let sentinel = Task { true }
    #expect(await sentinel.value)
    provider.cancel()

    #expect(await read.value == .cancelled)
    await operations.destroyed.wait()
    #expect(!operations.destroyedWhileReading.withLock { $0 })
}

@Test func audioReadCancellationReturnsCancellationAndDestroysAfterReadExit() async throws {
    let operations = BlockingAudioReaderOperations(resultAfterCancellation: .cancelled)
    let provider = FFmpegCompressedAudioSampleProvider(operations: operations)
    try await provider.prepare(
        url: URL(fileURLWithPath: "/fixtures/blocking-audio.mkv"),
        asset: nil,
        startTime: .zero,
        streamIndex: nil
    )

    let read = Task { await audioReadVerdict(from: provider) }
    await operations.readEntered.wait()

    let sentinel = Task { true }
    #expect(await sentinel.value)
    provider.cancel()

    #expect(await read.value == .cancelled)
    await operations.destroyed.wait()
    #expect(!operations.destroyedWhileReading.withLock { $0 })
}

@Test func blockedVideoReaderDoesNotBlockAudioReaderLane() async throws {
    let videoOperations = BlockingVideoReaderOperations(resultAfterCancellation: .cancelled)
    let audioOperations = ImmediateAudioReaderOperations()
    let videoProvider = FFmpegSampleProvider(operations: videoOperations)
    let audioProvider = FFmpegCompressedAudioSampleProvider(operations: audioOperations)
    let url = URL(fileURLWithPath: "/fixtures/independent-reader-lanes.mkv")
    try await videoProvider.prepare(url: url, asset: nil, startTime: .zero)
    try await audioProvider.prepare(
        url: url,
        asset: nil,
        startTime: .zero,
        streamIndex: nil
    )

    let videoRead = Task { await videoReadVerdict(from: videoProvider) }
    await videoOperations.readEntered.wait()
    let audioRead = Task { await audioReadVerdict(from: audioProvider) }
    #expect(await audioRead.value == .ended)

    videoProvider.cancel()
    #expect(await videoRead.value == .cancelled)
    audioProvider.cancel()
}

private enum ProviderReadVerdict: Sendable, Equatable {
    case cancelled
    case ended
    case sample
    case unexpectedEvent
    case failure(String)
}

private func videoReadVerdict(from provider: FFmpegSampleProvider) async -> ProviderReadVerdict {
    do {
        switch try await provider.nextEvent() {
        case .end: return .ended
        case .sample: return .sample
        case .formatChanged, .flush: return .unexpectedEvent
        }
    } catch is CancellationError {
        return .cancelled
    } catch {
        return .failure(String(describing: error))
    }
}

private func audioReadVerdict(
    from provider: FFmpegCompressedAudioSampleProvider
) async -> ProviderReadVerdict {
    do {
        return try await provider.copyNextSample() == nil ? .ended : .sample
    } catch is CancellationError {
        return .cancelled
    } catch {
        return .failure(String(describing: error))
    }
}

private final class BlockingVideoReaderOperations: FFmpegVideoReaderOperations, @unchecked Sendable {
    let readEntered = AsyncSignal()
    let destroyed = AsyncSignal()
    let destroyedWhileReading = TestLockedBox(false)

    private let resultAfterCancellation: FFmpegVideoReadOutcome
    private let releaseRead = DispatchSemaphore(value: 0)
    private let reading = TestLockedBox(false)

    init(resultAfterCancellation: FFmpegVideoReadOutcome) {
        self.resultAfterCancellation = resultAfterCancellation
    }

    func allocate() -> FFmpegVideoReaderHandle? {
        FFmpegVideoReaderHandle(pointer: OpaquePointer(bitPattern: 0x101)!)
    }

    func open(
        _ reader: FFmpegVideoReaderHandle,
        source: String,
        startSeconds: Double
    ) throws -> VideoSampleProviderInfo {
        VideoSampleProviderInfo(providerKind: "BlockingVideoTest")
    }

    func copyNextSample(from reader: FFmpegVideoReaderHandle) throws -> FFmpegVideoReadOutcome {
        reading.withLock { $0 = true }
        readEntered.signal()
        releaseRead.wait()
        reading.withLock { $0 = false }
        return resultAfterCancellation
    }

    func cancel(_ reader: FFmpegVideoReaderHandle) {
        releaseRead.signal()
    }

    func destroy(_ reader: FFmpegVideoReaderHandle) {
        destroyedWhileReading.withLock { $0 = reading.withLock { $0 } }
        destroyed.signal()
    }
}

private final class BlockingAudioReaderOperations: FFmpegAudioReaderOperations, @unchecked Sendable {
    let readEntered = AsyncSignal()
    let destroyed = AsyncSignal()
    let destroyedWhileReading = TestLockedBox(false)

    private let resultAfterCancellation: FFmpegAudioReadOutcome
    private let releaseRead = DispatchSemaphore(value: 0)
    private let reading = TestLockedBox(false)

    init(resultAfterCancellation: FFmpegAudioReadOutcome) {
        self.resultAfterCancellation = resultAfterCancellation
    }

    func allocate() -> FFmpegAudioReaderHandle? {
        FFmpegAudioReaderHandle(pointer: OpaquePointer(bitPattern: 0x201)!)
    }

    func open(
        _ reader: FFmpegAudioReaderHandle,
        source: String,
        startSeconds: Double,
        streamIndex: Int?
    ) throws -> AudioSampleProviderInfo {
        AudioSampleProviderInfo(
            providerKind: "BlockingAudioTest",
            streamIndex: 1,
            codecName: "aac",
            sampleRate: 48_000,
            channelCount: 2
        )
    }

    func copyNextSample(from reader: FFmpegAudioReaderHandle) throws -> FFmpegAudioReadOutcome {
        reading.withLock { $0 = true }
        readEntered.signal()
        releaseRead.wait()
        reading.withLock { $0 = false }
        return resultAfterCancellation
    }

    func cancel(_ reader: FFmpegAudioReaderHandle) {
        releaseRead.signal()
    }

    func destroy(_ reader: FFmpegAudioReaderHandle) {
        destroyedWhileReading.withLock { $0 = reading.withLock { $0 } }
        destroyed.signal()
    }
}

private struct ImmediateAudioReaderOperations: FFmpegAudioReaderOperations {
    func allocate() -> FFmpegAudioReaderHandle? {
        FFmpegAudioReaderHandle(pointer: OpaquePointer(bitPattern: 0x301)!)
    }

    func open(
        _ reader: FFmpegAudioReaderHandle,
        source: String,
        startSeconds: Double,
        streamIndex: Int?
    ) throws -> AudioSampleProviderInfo {
        AudioSampleProviderInfo(
            providerKind: "ImmediateAudioTest",
            streamIndex: 1,
            codecName: "aac",
            sampleRate: 48_000,
            channelCount: 2
        )
    }

    func copyNextSample(from reader: FFmpegAudioReaderHandle) throws -> FFmpegAudioReadOutcome {
        .end
    }

    func cancel(_ reader: FFmpegAudioReaderHandle) {}
    func destroy(_ reader: FFmpegAudioReaderHandle) {}
}

private final class TestLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try lock.withLock { try body(&value) }
    }
}

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSignals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            guard !waiters.isEmpty else {
                pendingSignals += 1
                return nil
            }
            return waiters.removeFirst()
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = lock.withLock {
                guard pendingSignals > 0 else {
                    waiters.append(continuation)
                    return false
                }
                pendingSignals -= 1
                return true
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }
}
