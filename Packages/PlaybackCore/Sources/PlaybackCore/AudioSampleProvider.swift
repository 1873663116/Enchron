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

private struct SendableAudioSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
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

final class FFmpegCompressedAudioSampleProvider: AudioSampleProvider {
    var info: AudioSampleProviderInfo? {
        readerLock.withLock { storedInfo }
    }

    private let readerLock = NSLock()
    private var storedInfo: AudioSampleProviderInfo?
    private var reader: OpaquePointer?

    func prepare(
        url: URL,
        asset: PlaybackAsset?,
        startTime: CMTime,
        streamIndex: Int?
    ) async throws {
        cancel()
        var error = [CChar](repeating: 0, count: 512)
        let newReader = FFmpegSourceLocator.argument(for: url).withCString { path in
            PBFFmpegAudioReaderCreate(
                path,
                startTime.seconds,
                Int32(streamIndex ?? -1),
                &error,
                error.count
            )
        }
        guard let newReader else {
            let message = Self.errorMessage(error)
            if message == "The selected source has no audio stream" {
                throw AudioSampleProviderError.noAudioStream
            }
            throw AudioSampleProviderError.open(message)
        }
        let newInfo = AudioSampleProviderInfo(
            providerKind: "FFmpegCompressedAudio",
            streamIndex: Int(PBFFmpegAudioReaderGetStreamIndex(newReader)),
            codecName: String(cString: PBFFmpegAudioReaderGetCodecName(newReader)),
            sampleRate: Int(PBFFmpegAudioReaderGetSampleRate(newReader)),
            channelCount: Int(PBFFmpegAudioReaderGetChannelCount(newReader))
        )
        readerLock.withLock {
            if let reader { PBFFmpegAudioReaderDestroy(reader) }
            reader = newReader
            storedInfo = newInfo
        }
    }

    func copyNextSample() async throws -> CMSampleBuffer? {
        try readerLock.withLock {
            guard let reader else { return nil }
            var sample: Unmanaged<CMSampleBuffer>?
            var error = [CChar](repeating: 0, count: 512)
            let result = PBFFmpegAudioReaderCopyNextSample(
                reader,
                &sample,
                &error,
                error.count
            )
            switch result {
            case PBFFmpegReadResultSample:
                return sample?.takeRetainedValue()
            case PBFFmpegReadResultEnd:
                return nil
            default:
                throw AudioSampleProviderError.read(Self.errorMessage(error))
            }
        }
    }

    func cancel() {
        readerLock.withLock {
            if let reader {
                PBFFmpegAudioReaderDestroy(reader)
                self.reader = nil
            }
            storedInfo = nil
        }
    }

    deinit {
        cancel()
    }

    private static func errorMessage(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    func tracks(in url: URL, asset: PlaybackAsset?) async throws -> [PlaybackAudioTrack] {
        FFmpegSourceLocator.argument(for: url).withCString { path in
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
        }
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
