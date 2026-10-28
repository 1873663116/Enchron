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

public enum StreamSessionActivity: String, Sendable, Equatable {
    case connecting
    case launching
    case waitingForVideo
    case requestingKeyframe
    case buffering
    case streaming

    public var title: String {
        switch self {
        case .connecting: "Connecting"
        case .launching: "Launching app"
        case .waitingForVideo: "Waiting for video"
        case .requestingKeyframe: "Requesting keyframe"
        case .buffering: "Buffering"
        case .streaming: "Streaming"
        }
    }

    public var showsLoading: Bool {
        self != .streaming
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

public extension StreamRecoveryAction {
    /// What the user can do about this class of failure. The launch alert shows
    /// it under the technical message so a failure is actionable, not just
    /// reported.
    var advice: String {
        switch self {
        case .none: String(localized: "这类失败没有可用的恢复动作。")
        case .retry: String(localized: "确认主机已开机且与本机在同一网络，然后重试。")
        case .reconnect: String(localized: "网络恢复后可以重新连接，串流会重新协商。")
        case .pairAgain: String(localized: "在主机上删除本设备的配对记录，然后重新配对。")
        case .repickApplication: String(localized: "先结束主机上正在运行的会话，或改选另一个应用。")
        }
    }
}

public extension StreamFailure {
    var categoryTitle: String {
        switch stage {
        case .pairing: String(localized: "配对失败")
        case .launch: String(localized: "无法启动应用")
        case .stream, .decode: String(localized: "串流中断")
        case .teardown: String(localized: "串流结束异常")
        case .discovery, .connect, .network: String(localized: "无法连接主机")
        case .applicationList: String(localized: "无法读取应用列表")
        }
    }
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
    public var gamepadEventsSent: Int64 = 0
    public var hardwareMouse = false
    public var pressedKeyCount: Int = 0
    public var pressedButtonCount: Int = 0

    public init() {}

    public var readableValue: String {
        var parts: [String] = []
        parts.append("mouse=\(mouseEventsSent)")
        parts.append("scroll=\(scrollEventsSent)")
        parts.append("keyboard=\(keyboardEventsSent)")
        parts.append("gamepad=\(gamepadEventsSent)")
        parts.append("hardwareMouse=\(hardwareMouse)")
        parts.append("pressedKeys=\(pressedKeyCount)")
        parts.append("pressedButtons=\(pressedButtonCount)")
        return parts.joined(separator: ";")
    }
}

public struct StreamDiagnostics: Sendable, Equatable {
    public var packetsReceived: Int64 = 0
    public var framesDecoded: Int64?
    public var framesPresented: Int64 = 0
    public var lastPresentedTimestampMs: Int64?
    public var networkDroppedFrames: Int64 = 0
    public var duplicatedFrames: Int64 = 0
    public var decodeRecoveries: Int64 = 0
    public var idrRequests: Int64 = 0
    public var queueDepth: Int = 0
    public var measuredBitrateKbps: Int?
    public var presentedFramesPerSecond: Int?
    public var estimatedRttMs: Int?
    public var estimatedRttVarianceMs: Int?
    public var hostAudioPlaying: Bool = false
    public var clientAudioOutput: Bool = true
    public var audioFramesReceived: Int64 = 0
    public var audioFramesEnqueued: Int64 = 0
    public var audioFramesDropped: Int64 = 0
    public var connectionQuality: Int32 = 0

    public init() {}

    public var readableSummary: String {
        var parts: [String] = []
        parts.append("quality=\(connectionQuality)")
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
    public var activity: StreamSessionActivity
    public var requested: StreamOptions
    public var negotiated: NegotiatedStreamConfiguration?
    public var input: StreamInputDiagnostics
    public var diagnostics: StreamDiagnostics
    public var failure: StreamFailure?
    public var adjustments: [StreamAdjustmentNotice]
    public var hdrModeReported: Bool

    public init(
        id: SessionID,
        hostID: HostID,
        appID: AppID,
        hostName: String,
        appName: String,
        state: StreamSessionState,
        activity: StreamSessionActivity = .connecting,
        requested: StreamOptions,
        negotiated: NegotiatedStreamConfiguration? = nil,
        input: StreamInputDiagnostics = StreamInputDiagnostics(),
        diagnostics: StreamDiagnostics = StreamDiagnostics(),
        failure: StreamFailure? = nil,
        adjustments: [StreamAdjustmentNotice] = [],
        hdrModeReported: Bool = false
    ) {
        self.id = id
        self.hostID = hostID
        self.appID = appID
        self.hostName = hostName
        self.appName = appName
        self.state = state
        self.activity = activity
        self.requested = requested
        self.negotiated = negotiated
        self.input = input
        self.diagnostics = diagnostics
        self.failure = failure
        self.adjustments = adjustments
        self.hdrModeReported = hdrModeReported
    }

    public var readableValue: String {
        var parts: [String] = []
        parts.append("session=\(state.readableValue)")
        parts.append("activity=\(activity.rawValue)")
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
