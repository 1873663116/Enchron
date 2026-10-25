import CoreMedia
import Foundation

public struct DiscoveredHost: Sendable, Equatable {
    public var instanceName: String
    public var address: HostAddress

    public init(instanceName: String, address: HostAddress) {
        self.instanceName = instanceName
        self.address = address
    }
}

public struct BackendCredentials: Sendable {
    public var address: HostAddress
    public var serverCert: Data?

    public init(address: HostAddress, serverCert: Data? = nil) {
        self.address = address
        self.serverCert = serverCert
    }
}

public struct BackendServerInfo: Sendable {
    public var name: String
    public var uniqueID: String
    public var pairStatus: Int
    public var httpsPort: UInt16
    public var appVersion: String
    public var gfeVersion: String?
    public var serverCodecModeSupport: UInt32
    public var state: String
    public var currentGame: String?

    public init(
        name: String,
        uniqueID: String,
        pairStatus: Int,
        httpsPort: UInt16,
        appVersion: String,
        gfeVersion: String?,
        serverCodecModeSupport: UInt32,
        state: String,
        currentGame: String?
    ) {
        self.name = name
        self.uniqueID = uniqueID
        self.pairStatus = pairStatus
        self.httpsPort = httpsPort
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.serverCodecModeSupport = serverCodecModeSupport
        self.state = state
        self.currentGame = currentGame
    }
}

public enum PairingOutcome: Sendable {
    case paired(serverCert: Data)
    case alreadyPaired(serverCert: Data?)
}

public protocol BackendPairingSession: AnyObject, Sendable {
    var pairingID: PairingID { get }
    var pin: String { get }
    func waitForOutcome() async throws -> PairingOutcome
    func cancel()
}

public struct BackendSessionRequest: Sendable {
    public var credentials: BackendCredentials
    public var appID: AppID
    public var appName: String
    public var options: StreamOptions

    public init(credentials: BackendCredentials, appID: AppID, appName: String, options: StreamOptions) {
        self.credentials = credentials
        self.appID = appID
        self.appName = appName
        self.options = options
    }
}

public enum BackendStagePhase: Sendable, Equatable {
    case starting
    case complete
    case failed(errorCode: Int32, portTestFlags: Int32)
}

public enum BackendSessionEvent: Sendable {
    case stage(name: String, phase: BackendStagePhase)
    case connected
    case terminated(errorCode: Int32)
    case statusUpdate(Int32)
    case hdrMode(Bool)
    case firstFramePresented
    case decoderConfigured(width: Int, height: Int, frameRate: Int, codec: String)
    case audioStarted(sampleRate: UInt32, channels: UInt32, samplesPerFrame: UInt32)
    case audioStopped
    case launchFailed(message: String)
}

public struct BackendAudioFrame: Sendable {
    public var pcm: Data
    public var channels: UInt32
    public var sampleRate: UInt32
    public var frameCount: UInt32

    public init(pcm: Data, channels: UInt32, sampleRate: UInt32, frameCount: UInt32) {
        self.pcm = pcm
        self.channels = channels
        self.sampleRate = sampleRate
        self.frameCount = frameCount
    }
}

public struct BackendVideoStats: Sendable {
    public var receivedFrames: Int
    public var networkDroppedFrames: Int
    public var totalFrames: Int
    public var submitGapCount: Int
    public var submitGapMaxMs: Int
    public var zeroCopyFrames: Int
    public var zeroCopyFallbacks: Int
    public var assembleMaxMs: Int
    public var queueWaitMaxMs: Int
    public var callbackMaxMs: Int
    public var pendingMax: Int
    public var decoderQos: Int
    public var framesWithHostProcessingLatency: Int
    public var averageHostProcessingLatencyMs: Double?
    public var measuredIntervalSeconds: Double

    public init(
        receivedFrames: Int,
        networkDroppedFrames: Int,
        totalFrames: Int,
        framesWithHostProcessingLatency: Int,
        averageHostProcessingLatencyMs: Double?,
        measuredIntervalSeconds: Double,
        submitGapCount: Int = 0,
        submitGapMaxMs: Int = 0,
        zeroCopyFrames: Int = 0,
        zeroCopyFallbacks: Int = 0,
        assembleMaxMs: Int = 0,
        queueWaitMaxMs: Int = 0,
        callbackMaxMs: Int = 0,
        pendingMax: Int = 0,
        decoderQos: Int = 0
    ) {
        self.receivedFrames = receivedFrames
        self.networkDroppedFrames = networkDroppedFrames
        self.totalFrames = totalFrames
        self.submitGapCount = submitGapCount
        self.submitGapMaxMs = submitGapMaxMs
        self.zeroCopyFrames = zeroCopyFrames
        self.zeroCopyFallbacks = zeroCopyFallbacks
        self.assembleMaxMs = assembleMaxMs
        self.queueWaitMaxMs = queueWaitMaxMs
        self.callbackMaxMs = callbackMaxMs
        self.pendingMax = pendingMax
        self.decoderQos = decoderQos
        self.framesWithHostProcessingLatency = framesWithHostProcessingLatency
        self.averageHostProcessingLatencyMs = averageHostProcessingLatencyMs
        self.measuredIntervalSeconds = measuredIntervalSeconds
    }
}

public protocol BackendSession: AnyObject, Sendable {
    var videoSampleHandler: (@Sendable (CMSampleBuffer) -> Void)? { get set }
    var audioFrameHandler: (@Sendable (BackendAudioFrame) -> Void)? { get set }
    var eventHandler: (@Sendable (BackendSessionEvent) -> Void)? { get set }

    var streamWidth: Int { get }
    var streamHeight: Int { get }
    var streamFrameRate: Int { get }

    func start()
    func stop()

    func sendMousePosition(normalizedX: Float, normalizedY: Float)
    func sendMouseMove(dx: Int32, dy: Int32)
    func sendMouseButton(code: Int32, down: Bool)
    func sendScroll(amount: Int32)
    func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32)
    func sendControllerState(
        buttonFlags: Int32,
        leftTrigger: UInt8,
        rightTrigger: UInt8,
        leftStickX: Int16,
        leftStickY: Int16,
        rightStickX: Int16,
        rightStickY: Int16
    )
    func sendControllerPresence(connected: Bool)
    func releaseAllInput()
    func requestIdrFrame()

    func estimatedRTT() -> (milliseconds: UInt32, variance: UInt32)?
    func videoStats() -> BackendVideoStats?
    func audioPendingPeakMs() -> Int
    func activeCodecName() -> String?
}

public protocol StreamingBackend: Sendable {
    func discoverHosts() -> AsyncStream<[DiscoveredHost]>
    func fetchServerInfo(_ credentials: BackendCredentials) async throws -> BackendServerInfo
    func beginPairing(_ credentials: BackendCredentials) async throws -> any BackendPairingSession
    func applications(_ credentials: BackendCredentials) async throws -> [HostApplication]
    func artwork(_ credentials: BackendCredentials, appID: AppID) async throws -> Data
    func launchSession(_ request: BackendSessionRequest) async throws -> any BackendSession
    func resumeSession(_ request: BackendSessionRequest) async throws -> any BackendSession
    func quitApplication(_ credentials: BackendCredentials) async throws
}
