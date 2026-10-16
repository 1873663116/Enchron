import Foundation

public enum StreamSessionState: Sendable, Equatable {
    case connecting(stage: String)
    case streaming
    case interrupted(reason: String)
    case stopping
    case ended(reason: String)

    public var readableValue: String {
        switch self {
        case .connecting(let stage): "connecting(stage=\(stage))"
        case .streaming: "streaming"
        case .interrupted(let reason): "interrupted(reason=\(reason))"
        case .stopping: "stopping"
        case .ended(let reason): "ended(reason=\(reason))"
        }
    }
}

public enum StreamVideoCodec: String, Sendable, Equatable {
    case h264
    case hevc
    case av1

    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "HEVC"
        case .av1: "AV1"
        }
    }
}

public struct NegotiatedStreamConfiguration: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var bitrateKbps: Int
    public var codec: StreamVideoCodec
    public var hostHdrActive: Bool
    public var audioChannels: Int

    public init(
        width: Int,
        height: Int,
        frameRate: Int,
        bitrateKbps: Int,
        codec: StreamVideoCodec,
        hostHdrActive: Bool,
        audioChannels: Int
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrateKbps = bitrateKbps
        self.codec = codec
        self.hostHdrActive = hostHdrActive
        self.audioChannels = audioChannels
    }

    public var readableValue: String {
        "\(width)x\(height)@\(frameRate);bitrate=\(bitrateKbps);codec=\(codec.rawValue);hdr=\(hostHdrActive)"
    }
}

public enum StreamFailureStage: String, Sendable, Equatable {
    case discovery
    case connect
    case pairing
    case applicationList
    case launch
    case stream
    case decode
    case network
    case teardown
}

public enum StreamFailureKind: String, Sendable, Equatable {
    case unreachable
    case duplicateHost
    case notPaired
    case pairingRejected
    case certificateMismatch
    case applicationMissing
    case applicationLaunchFailed
    case hostBusy
    case connectionRefused
    case connectionLost
    case decodeFailed
    case configurationRejected
    case cancelled
    case unknown
}

public enum StreamRecoveryAction: String, Sendable, Equatable {
    case none
    case retry
    case reconnect
    case pairAgain
    case repickApplication
}

public struct StreamFailure: LocalizedError, Sendable, Equatable {
    public var stage: StreamFailureStage
    public var kind: StreamFailureKind
    public var message: String
    public var recovery: StreamRecoveryAction
    public var upstreamDetail: String?

    public init(
        stage: StreamFailureStage,
        kind: StreamFailureKind,
        message: String,
        recovery: StreamRecoveryAction,
        upstreamDetail: String? = nil
    ) {
        self.stage = stage
        self.kind = kind
        self.message = message
        self.recovery = recovery
        self.upstreamDetail = upstreamDetail
    }

    public var readableValue: String {
        "stage=\(stage.rawValue);kind=\(kind.rawValue);recovery=\(recovery.rawValue);message=\(message)"
    }

    public var errorDescription: String? {
        var description = "\(message)（\(stage.rawValue)/\(kind.rawValue)）"
        if let upstreamDetail {
            description += " [\(upstreamDetail)]"
        }
        return description
    }
}

public struct StreamInputDiagnostics: Sendable, Equatable {
    public var mouseEventsSent: Int64 = 0
    public var scrollEventsSent: Int64 = 0
    public var keyboardEventsSent: Int64 = 0
    public var pressedKeyCount: Int = 0
    public var pressedButtonCount: Int = 0

    public init() {}

    public var readableValue: String {
        "mouse=\(mouseEventsSent);scroll=\(scrollEventsSent);keyboard=\(keyboardEventsSent);pressedKeys=\(pressedKeyCount);pressedButtons=\(pressedButtonCount)"
    }
}

public struct StreamDiagnostics: Sendable, Equatable {
    public var packetsReceived: Int64 = 0
    public var framesDecoded: Int64? = nil
    public var framesPresented: Int64 = 0
    public var lastPresentedTimestampMs: Int64? = nil
    public var networkDroppedFrames: Int64 = 0
    public var duplicatedFrames: Int64 = 0
    public var decodeRecoveries: Int64 = 0
    public var idrRequests: Int64 = 0
    public var queueDepth: Int = 0
    public var estimatedRttMs: Int? = nil
    public var estimatedRttVarianceMs: Int? = nil
    public var hostAudioPlaying: Bool = false
    public var clientAudioOutput: Bool = true
    public var audioFramesReceived: Int64 = 0
    public var audioFramesEnqueued: Int64 = 0
    public var audioFramesDropped: Int64 = 0

    public init() {}

    public var readableSummary: String {
        var parts: [String] = []
        parts.append("packets=\(packetsReceived)")
        parts.append("presented=\(framesPresented)")
        if let framesDecoded {
            parts.append("decoded=\(framesDecoded)")
        }
        if let lastPresentedTimestampMs {
            parts.append("lastPresented=\(lastPresentedTimestampMs)")
        }
        parts.append("dropped=\(networkDroppedFrames)")
        parts.append("decodeRecoveries=\(decodeRecoveries)")
        parts.append("idrRequests=\(idrRequests)")
        parts.append("queue=\(queueDepth)")
        if let estimatedRttMs {
            parts.append("netRttMs=\(estimatedRttMs)")
        }
        parts.append("hostAudio=\(hostAudioPlaying)")
        parts.append("clientAudio=\(clientAudioOutput)")
        if framesPresented > 0 || audioFramesReceived > 0 {
            parts.append("audio:received=\(audioFramesReceived)")
            parts.append("audio:enqueued=\(audioFramesEnqueued)")
            parts.append("audio:dropped=\(audioFramesDropped)")
        }
        return parts.joined(separator: ";")
    }
}

public struct StreamAdjustmentNotice: Sendable, Equatable {
    public var summary: String
    public var detail: String

    public init(summary: String, detail: String) {
        self.summary = summary
        self.detail = detail
    }
}

public struct SessionSnapshot: Sendable, Identifiable {
    public var id: SessionID
    public var hostID: HostID
    public var appID: AppID
    public var hostName: String
    public var appName: String
    public var state: StreamSessionState
    public var requested: StreamOptions
    public var negotiated: NegotiatedStreamConfiguration?
    public var input: StreamInputDiagnostics
    public var diagnostics: StreamDiagnostics
    public var failure: StreamFailure?
    public var adjustments: [StreamAdjustmentNotice]

    public init(
        id: SessionID,
        hostID: HostID,
        appID: AppID,
        hostName: String,
        appName: String,
        state: StreamSessionState,
        requested: StreamOptions,
        negotiated: NegotiatedStreamConfiguration? = nil,
        input: StreamInputDiagnostics = StreamInputDiagnostics(),
        diagnostics: StreamDiagnostics = StreamDiagnostics(),
        failure: StreamFailure? = nil,
        adjustments: [StreamAdjustmentNotice] = []
    ) {
        self.id = id
        self.hostID = hostID
        self.appID = appID
        self.hostName = hostName
        self.appName = appName
        self.state = state
        self.requested = requested
        self.negotiated = negotiated
        self.input = input
        self.diagnostics = diagnostics
        self.failure = failure
        self.adjustments = adjustments
    }

    public var readableValue: String {
        var parts: [String] = []
        parts.append("session=\(state.readableValue)")
        parts.append("host=\(hostName)")
        parts.append("app=\(appName)")
        parts.append("requested=\(requested.readableValue)")
        if let negotiated {
            parts.append("negotiated=\(negotiated.readableValue)")
        } else {
            parts.append("negotiated=unavailable")
        }
        parts.append(diagnostics.readableSummary)
        parts.append("input:\(input.readableValue)")
        if let failure {
            parts.append("failure=\(failure.readableValue)")
        }
        parts.append("adjustments=\(adjustments.count)")
        return parts.joined(separator: ";")
    }
}
