import CoreMedia
import Foundation

public struct MoonlightHostAddress: Hashable, Sendable {
    public var host: String
    public var portBase: UInt16

    public static let defaultPortBase: UInt16 = 47989

    public init(host: String, portBase: UInt16 = MoonlightHostAddress.defaultPortBase) {
        self.host = host
        self.portBase = portBase
    }

    public var portOffset: Int { Int(portBase) - Int(MoonlightHostAddress.defaultPortBase) }

    /// The HTTPS service of the same port family. Zero means the family runs on
    /// the default base, where the host itself advertises the port.
    public var httpsPort: UInt16 {
        portOffset == 0 ? 0 : UInt16(clamping: Int(portBase) - 5)
    }

    public var addressPortString: String {
        host.contains(":") ? "[\(host)]:\(portBase)" : "\(host):\(portBase)"
    }
}

public struct MoonlightServerInfo: Sendable {
    public var name: String
    public var uniqueID: String
    public var pairStatus: Int
    public var httpsPort: UInt16
    public var appVersion: String
    public var gfeVersion: String?
    public var serverCodecModeSupport: UInt32
    public var state: String
    public var currentGame: String?
}

public struct MoonlightApplication: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var hdrSupported: Bool
}

public enum MoonlightPairingOutcome: Sendable {
    case paired(serverCert: Data)
    case alreadyPaired
    case failed(String)
    case cancelled
}

public struct MoonlightStreamRequest: Sendable {
    public var address: MoonlightHostAddress
    public var serverCert: Data?
    public var appID: String
    public var appName: String
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var bitrateKbps: Int
    public var codec: MoonlightVideoCodec
    public var hdrEnabled: Bool
    public var playAudioOnPC: Bool
    public var optimizeGameSettings: Bool
    public var gamepadMask: Int

    public init(
        address: MoonlightHostAddress,
        serverCert: Data?,
        appID: String,
        appName: String,
        width: Int,
        height: Int,
        frameRate: Int,
        bitrateKbps: Int,
        codec: MoonlightVideoCodec,
        hdrEnabled: Bool,
        playAudioOnPC: Bool = false,
        optimizeGameSettings: Bool = false,
        gamepadMask: Int = 0
    ) {
        self.address = address
        self.serverCert = serverCert
        self.appID = appID
        self.appName = appName
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.bitrateKbps = bitrateKbps
        self.codec = codec
        self.hdrEnabled = hdrEnabled
        self.playAudioOnPC = playAudioOnPC
        self.optimizeGameSettings = optimizeGameSettings
        self.gamepadMask = gamepadMask
    }
}

public enum MoonlightVideoCodec: String, Sendable {
    case auto
    case h264
    case hevc
    case av1
}

public enum MoonlightStagePhase: Sendable, Equatable {
    case starting
    case complete
    case failed(errorCode: Int32, portTestFlags: Int32)
}

public enum MoonlightSessionEvent: Sendable {
    case stage(name: String, phase: MoonlightStagePhase)
    case connected
    case terminated(errorCode: Int32)
    case statusUpdate(Int32)
    case hdrMode(Bool)
    case firstFramePresented
    case decoderConfigured(width: Int, height: Int, frameRate: Int, codec: MoonlightVideoCodec)
    case audioStarted(channelCount: UInt32, sampleRate: UInt32, samplesPerFrame: UInt32)
    case audioStopped
}

public struct MoonlightAudioFrame: Sendable {
    public var pcm: Data
    public var channelCount: UInt32
    public var sampleRate: UInt32
    public var frameCount: UInt32
}

public struct MoonlightVideoStats: Sendable {
    public var receivedFrames: Int
    public var networkDroppedFrames: Int
    public var totalFrames: Int
    public var framesWithHostProcessingLatency: Int
    public var averageHostProcessingLatencyMs: Double?
    public var measuredIntervalSeconds: Double
    public var submitGapCount: Int
    public var submitGapMaxMs: Int
    public var zeroCopyFrames: Int
    public var zeroCopyFallbacks: Int
    public var assembleMaxMs: Int
    public var queueWaitMaxMs: Int
    public var callbackMaxMs: Int
    public var pendingMax: Int
    public var decoderQos: Int
}

public enum MoonlightClientError: Error, Sendable {
    case unreachable(String)
    case notPaired
    case hostBusy(String)
    case hostOccupied(String)
    case launchRejected(String)
    case sessionMissing
    case cancelled
    case upstream(String)
}

public enum MoonlightLaunchPreference: Sendable {
    case automatic
    case resumeOnly
    case launchOnly
}

public enum MoonlightControllerType: UInt8, Sendable {
    case unknown = 0
    case xbox = 1
    case playStation = 2
    case nintendo = 3
    case steam = 4
}

public struct MoonlightControllerArrival: Sendable, Equatable {
    public var controllerNumber: UInt8
    public var activeGamepadMask: UInt16
    public var type: MoonlightControllerType
    public var supportedButtons: UInt32
    public var capabilities: UInt16

    public init(
        controllerNumber: UInt8,
        activeGamepadMask: UInt16,
        type: MoonlightControllerType,
        supportedButtons: UInt32,
        capabilities: UInt16
    ) {
        self.controllerNumber = controllerNumber
        self.activeGamepadMask = activeGamepadMask
        self.type = type
        self.supportedButtons = supportedButtons
        self.capabilities = capabilities
    }
}

public enum MoonlightControllerFeedback: Sendable, Equatable {
    case rumble(controllerNumber: UInt16, lowFrequency: UInt16, highFrequency: UInt16)
    case triggerRumble(controllerNumber: UInt16, leftTrigger: UInt16, rightTrigger: UInt16)
    case motionRequest(controllerNumber: UInt16, motionType: UInt8, reportRateHz: UInt16)
    case led(controllerNumber: UInt16, red: UInt8, green: UInt8, blue: UInt8)
}
