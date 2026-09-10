import Foundation
import PlaybackFFmpegBridge

public enum PlaybackDemuxBufferPreference: Sendable, Equatable {
    case none
    case automatic
    case bytes(Int64)
}

public enum PlaybackSourceTransport: Sendable, Equatable {
    case localFile
    case remoteByteStream(buffering: PlaybackDemuxBufferPreference)

    var isRemote: Bool {
        switch self {
        case .localFile: false
        case .remoteByteStream: true
        }
    }

    var bufferPreference: PlaybackDemuxBufferPreference {
        switch self {
        case .localFile: .none
        case .remoteByteStream(let buffering): buffering
        }
    }
}

public struct PlaybackDemuxBufferDiagnostics: Sendable, Equatable {
    public enum Mode: String, Sendable, Equatable {
        case none
        case automatic
        case bytes
    }

    public let mode: Mode
    public let bufferedDurationSeconds: Double
    public let targetDurationSeconds: Double
    public let forwardBufferedBytes: Int64
    public let forwardLimitBytes: Int64
    // Read-ahead of streams the video does not need. Held apart from
    // forwardBufferedBytes because it can never park the read thread.
    public let auxiliaryBufferedBytes: Int64
    public let backwardBufferedBytes: Int64
    public let backwardLimitBytes: Int64
    public let reconnectAttemptCount: UInt32
    public let readFrameCount: UInt64
}

enum PlaybackDemuxBufferConfigurationError: LocalizedError {
    case invalidExplicitByteLimit(Int64)
    case invalidOverride(name: String, value: String)

    var errorDescription: String? {
        switch self {
        case .invalidExplicitByteLimit(let value):
            "The demux buffer byte limit must be positive, not \(value)."
        case .invalidOverride(let name, let value):
            "The demux buffer override \(name)=\(value) is invalid."
        }
    }
}

extension PBFFmpegDemuxBufferConfiguration {
    static func playbackConfiguration(
        for preference: PlaybackDemuxBufferPreference,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        let mode: PBFFmpegDemuxBufferMode
        let explicitForwardByteLimit: Int64
        switch preference {
        case .none:
            mode = PBFFmpegDemuxBufferModeNone
            explicitForwardByteLimit = 0
        case .automatic:
            mode = PBFFmpegDemuxBufferModeAutomatic
            explicitForwardByteLimit = 0
        case .bytes(let byteLimit):
            guard byteLimit > 0 else {
                throw PlaybackDemuxBufferConfigurationError.invalidExplicitByteLimit(byteLimit)
            }
            mode = PBFFmpegDemuxBufferModeBytes
            explicitForwardByteLimit = byteLimit
        }

        var configuration = PBFFmpegDemuxBufferConfigurationMake(
            mode,
            explicitForwardByteLimit
        )
        try applyPositiveInt64Override(
            "ENCHRON_DEMUX_FORWARD_BUFFER_BYTES",
            from: environment,
            to: &configuration.forwardByteLimit
        )
        try applyNonnegativeInt64Override(
            "ENCHRON_DEMUX_BACKWARD_BUFFER_BYTES",
            from: environment,
            to: &configuration.backwardByteLimit
        )
        try applyPositiveDoubleOverride(
            mode == PBFFmpegDemuxBufferModeNone
                ? "ENCHRON_DEMUX_NON_CACHE_SECONDS"
                : "ENCHRON_DEMUX_CACHE_SECONDS",
            from: environment,
            to: &configuration.targetDurationSeconds
        )
        return configuration
    }
}

private func applyPositiveInt64Override(
    _ name: String,
    from environment: [String: String],
    to value: inout Int64
) throws {
    guard let raw = environment[name] else { return }
    guard let parsed = Int64(raw), parsed > 0 else {
        throw PlaybackDemuxBufferConfigurationError.invalidOverride(name: name, value: raw)
    }
    value = parsed
}

private func applyNonnegativeInt64Override(
    _ name: String,
    from environment: [String: String],
    to value: inout Int64
) throws {
    guard let raw = environment[name] else { return }
    guard let parsed = Int64(raw), parsed >= 0 else {
        throw PlaybackDemuxBufferConfigurationError.invalidOverride(name: name, value: raw)
    }
    value = parsed
}

private func applyPositiveDoubleOverride(
    _ name: String,
    from environment: [String: String],
    to value: inout Double
) throws {
    guard let raw = environment[name] else { return }
    guard let parsed = Double(raw), parsed.isFinite, parsed > 0 else {
        throw PlaybackDemuxBufferConfigurationError.invalidOverride(name: name, value: raw)
    }
    value = parsed
}
