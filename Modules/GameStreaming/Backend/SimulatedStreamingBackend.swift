import AVFoundation
import Foundation

public final class SimulatedStreamingBackend: StreamingBackend, @unchecked Sendable {
    public init() {}

    public func discoverHosts() -> AsyncStream<[DiscoveredHost]> {
        AsyncStream { continuation in
            let host = DiscoveredHost(instanceName: "Enchron Acceptance Host", address: HostAddress(host: "127.0.0.1"))
            continuation.yield([host])
            continuation.finish()
        }
    }

    public func fetchServerInfo(_ credentials: BackendCredentials) async throws -> BackendServerInfo {
        try await Task.sleep(for: .milliseconds(120))
        return BackendServerInfo(
            name: "Enchron Acceptance Host",
            uniqueID: "SIM-" + credentials.address.displayString,
            pairStatus: 0,
            httpsPort: credentials.address.httpsPort,
            appVersion: "7.1.431.-1",
            gfeVersion: nil,
            serverCodecModeSupport: 0,
            state: "SUNSHINE_SERVER_FREE",
            currentGame: nil
        )
    }

    public func beginPairing(_ credentials: BackendCredentials) async throws -> any BackendPairingSession {
        try await Task.sleep(for: .milliseconds(150))
        return SimulatedPairingSession()
    }

    public func applications(_ credentials: BackendCredentials) async throws -> [HostApplication] {
        try await Task.sleep(for: .milliseconds(150))
        return [
            HostApplication(id: AppID(rawValue: "sim-bigpicture"), name: "Steam Big Picture", hdrSupported: true),
            HostApplication(id: AppID(rawValue: "sim-desktop"), name: "Desktop", hdrSupported: true),
            HostApplication(id: AppID(rawValue: "sim-probe"), name: "Enchron Probe", hdrSupported: false)
        ]
    }

    public func artwork(_ credentials: BackendCredentials, appID: AppID) async throws -> Data {
        throw StreamFailure(
            stage: .applicationList,
            kind: .applicationMissing,
            message: "模拟后端不提供图标",
            recovery: .none
        )
    }

    public func launchSession(_ request: BackendSessionRequest) async throws -> any BackendSession {
        try await Task.sleep(for: .milliseconds(300))
        return SimulatedSession(request: request)
    }

    public func resumeSession(_ request: BackendSessionRequest) async throws -> any BackendSession {
        try await Task.sleep(for: .milliseconds(200))
        return SimulatedSession(request: request)
    }

    public func quitApplication(_ credentials: BackendCredentials) async throws {
        try await Task.sleep(for: .milliseconds(100))
    }
}

private final class SimulatedPairingSession: BackendPairingSession, @unchecked Sendable {
    let pairingID = PairingID()
    let pin = "1234"
    private(set) var cancelled = false

    func waitForOutcome() async throws -> PairingOutcome {
        try await Task.sleep(for: .seconds(2))
        if cancelled {
            throw StreamFailure(stage: .pairing, kind: .cancelled, message: "已取消", recovery: .none)
        }
        return .paired(serverCert: Data("simulated-cert".utf8))
    }

    func cancel() {
        cancelled = true
    }
}

private final class SimulatedSession: BackendSession, @unchecked Sendable {
    var videoSampleHandler: (@Sendable (CMSampleBuffer) -> Void)?
    var audioFrameHandler: (@Sendable (BackendAudioFrame) -> Void)?
    var eventHandler: (@Sendable (BackendSessionEvent) -> Void)?

    let streamWidth: Int
    let streamHeight: Int
    let streamFrameRate: Int

    private let request: BackendSessionRequest
    private var running = false

    init(request: BackendSessionRequest) {
        self.request = request
        self.streamWidth = request.options.resolution.width
        self.streamHeight = request.options.resolution.height
        self.streamFrameRate = request.options.frameRate
    }

    func start() {
        running = true
        let events = eventHandler
        Task {
            events?(.stage(name: "ri key exchange", phase: .starting))
            try? await Task.sleep(for: .milliseconds(400))
            events?(.stage(name: "ri key exchange", phase: .complete))
            events?(.stage(name: "video setup", phase: .starting))
            try? await Task.sleep(for: .milliseconds(400))
            events?(.stage(name: "video setup", phase: .complete))
            events?(.connected)
            events?(.decoderConfigured(
                width: self.streamWidth,
                height: self.streamHeight,
                frameRate: self.streamFrameRate,
                codec: self.request.options.codec == .h264 ? "h264" : "hevc"
            ))
            try? await Task.sleep(for: .milliseconds(300))
            events?(.audioStarted(sampleRate: 48_000, channels: 2, samplesPerFrame: 960))
            events?(.firstFramePresented)
        }
    }

    func stop() {
        running = false
        let events = eventHandler
        Task {
            events?(.terminated(errorCode: 0))
        }
    }

    func sendMousePosition(normalizedX: Float, normalizedY: Float) {}
    func sendMouseMove(dx: Int32, dy: Int32) {}
    func sendMouseButton(code: Int32, down: Bool) {}
    func sendScroll(amount: Int32) {}
    func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32) {}
    func sendControllerState(
        buttonFlags: Int32,
        leftTrigger: UInt8,
        rightTrigger: UInt8,
        leftStickX: Int16,
        leftStickY: Int16,
        rightStickX: Int16,
        rightStickY: Int16
    ) {}
    func sendControllerPresence(connected: Bool) {}
    func releaseAllInput() {}
    func requestIdrFrame() {}
    func estimatedRTT() -> (milliseconds: UInt32, variance: UInt32)? { (2, 1) }

    func videoStats() -> BackendVideoStats? {
        BackendVideoStats(
            receivedFrames: 0,
            networkDroppedFrames: 0,
            totalFrames: 0,
            framesWithHostProcessingLatency: 0,
            averageHostProcessingLatencyMs: nil,
            measuredIntervalSeconds: 1
        )
    }

    func activeCodecName() -> String? { nil }
}
