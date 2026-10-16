import CMoonlightCore
import CoreMedia
import Foundation
import MoonlightClient

public final class MoonlightStreamingBackend: StreamingBackend, @unchecked Sendable {
    public static let shared = MoonlightStreamingBackend()

    private let service = MoonlightService()
    private let discovery = MoonlightDiscovery()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base
            .appendingPathComponent("Enchron", isDirectory: true)
            .appendingPathComponent("moonlight-identity", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        MoonlightService.configure(
            storageDirectory: directory.path,
            deviceName: "Enchron Vision"
        )
    }

    public func discoverHosts() -> AsyncStream<[DiscoveredHost]> {
        let upstream = discovery.start()
        return AsyncStream { continuation in
            let task = Task {
                for await batch in upstream {
                    guard !Task.isCancelled else { return }
                    continuation.yield(batch.map { host in
                        DiscoveredHost(
                            instanceName: host.instanceName,
                            address: HostAddress(
                                host: host.host,
                                portBase: host.port == 0 ? HostAddress.defaultPortBase : host.port
                            )
                        )
                    })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func fetchServerInfo(_ credentials: BackendCredentials) async throws -> BackendServerInfo {
        do {
            let info = try await service.fetchServerInfo(
                address: credentials.address.moonlightAddress,
                serverCert: credentials.serverCert
            )
            return BackendServerInfo(
                name: info.name,
                uniqueID: info.uniqueID,
                pairStatus: info.pairStatus,
                httpsPort: info.httpsPort,
                appVersion: info.appVersion,
                gfeVersion: info.gfeVersion,
                serverCodecModeSupport: info.serverCodecModeSupport,
                state: info.state,
                currentGame: info.currentGame
            )
        } catch let error as MoonlightClientError {
            throw Self.failure(from: error, stage: .connect)
        } catch {
            throw StreamFailure(
                stage: .connect,
                kind: .unknown,
                message: "主机请求失败",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
        }
    }

    public func beginPairing(_ credentials: BackendCredentials) async throws -> any BackendPairingSession {
        do {
            let session = try await service.beginPairing(
                address: credentials.address.moonlightAddress,
                serverCert: credentials.serverCert
            )
            let pin = try await session.pin()
            return MoonlightPairingAdapter(session: session, pin: pin)
        } catch let error as MoonlightClientError {
            throw Self.failure(from: error, stage: .pairing)
        } catch {
            throw StreamFailure(
                stage: .pairing,
                kind: .unknown,
                message: "配对无法开始",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
        }
    }

    public func applications(_ credentials: BackendCredentials) async throws -> [HostApplication] {
        do {
            let applications = try await service.fetchApplications(
                address: credentials.address.moonlightAddress,
                serverCert: credentials.serverCert
            )
            return applications.map { application in
                HostApplication(
                    id: AppID(rawValue: application.id),
                    name: application.name,
                    hdrSupported: application.hdrSupported
                )
            }
        } catch let error as MoonlightClientError {
            throw Self.failure(from: error, stage: .applicationList)
        } catch {
            throw StreamFailure(
                stage: .applicationList,
                kind: .unknown,
                message: "应用列表读取失败",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
        }
    }

    public func artwork(_ credentials: BackendCredentials, appID: AppID) async throws -> Data {
        do {
            return try await service.fetchArtwork(
                address: credentials.address.moonlightAddress,
                serverCert: credentials.serverCert,
                appID: appID.rawValue
            )
        } catch let error as MoonlightClientError {
            throw Self.failure(from: error, stage: .applicationList)
        } catch {
            throw StreamFailure(
                stage: .applicationList,
                kind: .unknown,
                message: "应用图标读取失败",
                recovery: .none,
                upstreamDetail: String(describing: error)
            )
        }
    }

    public func launchSession(_ request: BackendSessionRequest) async throws -> any BackendSession {
        try await startSession(request, preference: .automatic)
    }

    public func resumeSession(_ request: BackendSessionRequest) async throws -> any BackendSession {
        try await startSession(request, preference: .resumeOnly)
    }

    private func startSession(
        _ request: BackendSessionRequest,
        preference: MoonlightLaunchPreference
    ) async throws -> any BackendSession {
        do {
            let session = try await service.startSession(
                MoonlightStreamRequest(
                    address: request.credentials.address.moonlightAddress,
                    serverCert: request.credentials.serverCert,
                    appID: request.appID.rawValue,
                    appName: request.appName,
                    width: request.options.resolution.width,
                    height: request.options.resolution.height,
                    frameRate: request.options.frameRate,
                    bitrateKbps: request.options.bitrateKbps,
                    codec: Self.codec(request.options.codec),
                    hdrEnabled: request.options.hdrEnabled && request.options.codec != .h264
                ),
                preference: preference
            )
            return MoonlightSessionAdapter(session: session)
        } catch let error as MoonlightClientError {
            throw Self.failure(from: error, stage: .launch)
        } catch {
            throw StreamFailure(
                stage: .launch,
                kind: .unknown,
                message: "无法启动串流",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
        }
    }

    public func quitApplication(_ credentials: BackendCredentials) async throws {
        do {
            try await service.quitApplication(
                address: credentials.address.moonlightAddress,
                serverCert: credentials.serverCert
            )
        } catch let error as MoonlightClientError {
            throw Self.failure(from: error, stage: .launch)
        } catch {
            throw StreamFailure(
                stage: .launch,
                kind: .unknown,
                message: "退出应用失败",
                recovery: .retry,
                upstreamDetail: String(describing: error)
            )
        }
    }

    private static func codec(_ preference: StreamCodecPreference) -> MoonlightVideoCodec {
        switch preference {
        case .auto: .auto
        case .h264: .h264
        case .hevc: .hevc
        case .av1: .av1
        }
    }

    private static func failure(from error: MoonlightClientError, stage: StreamFailureStage) -> StreamFailure {
        switch error {
        case .unreachable(let detail):
            StreamFailure(
                stage: stage,
                kind: .unreachable,
                message: "主机不可达",
                recovery: .retry,
                upstreamDetail: detail
            )
        case .notPaired:
            StreamFailure(
                stage: .pairing,
                kind: .notPaired,
                message: "主机未配对",
                recovery: .pairAgain
            )
        case .hostBusy(let detail):
            StreamFailure(
                stage: .launch,
                kind: .hostBusy,
                message: "主机上没有可恢复的会话",
                recovery: .retry,
                upstreamDetail: detail
            )
        case .launchRejected(let detail):
            StreamFailure(
                stage: .launch,
                kind: .applicationLaunchFailed,
                message: "主机拒绝了启动请求",
                recovery: .retry,
                upstreamDetail: detail
            )
        case .sessionMissing:
            StreamFailure(
                stage: .launch,
                kind: .connectionLost,
                message: "会话不存在",
                recovery: .reconnect
            )
        case .cancelled:
            StreamFailure(
                stage: stage,
                kind: .cancelled,
                message: "已取消",
                recovery: .none
            )
        case .upstream(let detail):
            StreamFailure(
                stage: stage,
                kind: .unknown,
                message: "协议栈错误",
                recovery: .retry,
                upstreamDetail: detail
            )
        }
    }
}

private extension HostAddress {
    var moonlightAddress: MoonlightHostAddress {
        MoonlightHostAddress(host: host, portBase: portBase)
    }
}

private final class MoonlightPairingAdapter: BackendPairingSession, @unchecked Sendable {
    let pairingID: PairingID
    let pin: String
    private let session: MoonlightPairingSession

    init(session: MoonlightPairingSession, pin: String) {
        self.session = session
        self.pairingID = PairingID(rawValue: session.pairingID.uuidString)
        self.pin = pin
    }

    func waitForOutcome() async throws -> PairingOutcome {
        switch try await session.outcome() {
        case .paired(let serverCert):
            return .paired(serverCert: serverCert)
        case .alreadyPaired:
            return .alreadyPaired(serverCert: nil)
        case .failed(let message):
            throw StreamFailure(
                stage: .pairing,
                kind: .pairingRejected,
                message: "配对被主机拒绝",
                recovery: .pairAgain,
                upstreamDetail: message
            )
        case .cancelled:
            throw StreamFailure(
                stage: .pairing,
                kind: .cancelled,
                message: "已取消",
                recovery: .none
            )
        }
    }

    func cancel() {
        session.cancel()
    }
}

private final class MoonlightSessionAdapter: BackendSession, @unchecked Sendable {
    var videoSampleHandler: (@Sendable (CMSampleBuffer) -> Void)?
    var audioFrameHandler: (@Sendable (BackendAudioFrame) -> Void)?
    var eventHandler: (@Sendable (BackendSessionEvent) -> Void)?

    private let session: MoonlightStreamSession

    init(session: MoonlightStreamSession) {
        self.session = session
        session.onVideoSample = { [weak self] sample in
            self?.videoSampleHandler?(sample)
        }
        session.onAudioFrame = { [weak self] frame in
            self?.audioFrameHandler?(BackendAudioFrame(
                pcm: frame.pcm,
                channels: frame.channelCount,
                sampleRate: frame.sampleRate,
                frameCount: frame.frameCount
            ))
        }
        session.onEvent = { [weak self] event in
            self?.eventHandler?(Self.map(event))
        }
    }

    var streamWidth: Int { session.streamWidth }
    var streamHeight: Int { session.streamHeight }
    var streamFrameRate: Int { session.streamFrameRate }

    func start() {
        session.start()
    }

    func stop() {
        session.stop()
    }

    func sendMousePosition(normalizedX: Float, normalizedY: Float) {
        session.sendMousePosition(normalizedX: normalizedX, normalizedY: normalizedY)
    }

    func sendMouseMove(dx: Int32, dy: Int32) {
        session.sendMouseMove(dx: dx, dy: dy)
    }

    func sendMouseButton(code: Int32, down: Bool) {
        session.sendMouseButton(code: code, down: down)
    }

    func sendScroll(amount: Int32) {
        session.sendScroll(amount: amount)
    }

    func sendKey(hidUsage: UInt32, down: Bool, modifierFlags: UInt32) {
        session.sendKey(hidUsage: hidUsage, down: down, modifierFlags: modifierFlags)
    }

    func releaseAllInput() {
        session.releaseAllInput()
    }

    func requestIdrFrame() {
        session.requestIdrFrame()
    }

    func estimatedRTT() -> (milliseconds: UInt32, variance: UInt32)? {
        session.estimatedRTT()
    }

    func videoStats() -> BackendVideoStats? {
        guard let stats = session.videoStats() else { return nil }
        return BackendVideoStats(
            receivedFrames: stats.receivedFrames,
            networkDroppedFrames: stats.networkDroppedFrames,
            totalFrames: stats.totalFrames,
            framesWithHostProcessingLatency: stats.framesWithHostProcessingLatency,
            averageHostProcessingLatencyMs: stats.averageHostProcessingLatencyMs,
            measuredIntervalSeconds: stats.measuredIntervalSeconds
        )
    }

    func activeCodecName() -> String? {
        session.activeCodecName
    }

    private static func map(_ event: MoonlightSessionEvent) -> BackendSessionEvent {
        switch event {
        case .stage(let name, let phase):
            switch phase {
            case .starting: .stage(name: name, phase: .starting)
            case .complete: .stage(name: name, phase: .complete)
            case .failed(let errorCode, let portTestFlags):
                .stage(name: name, phase: .failed(errorCode: errorCode, portTestFlags: portTestFlags))
            }
        case .connected:
            .connected
        case .terminated(let errorCode):
            .terminated(errorCode: errorCode)
        case .statusUpdate(let status):
            .statusUpdate(status)
        case .hdrMode(let enabled):
            .hdrMode(enabled)
        case .firstFramePresented:
            .firstFramePresented
        case .decoderConfigured(let width, let height, let frameRate, let codec):
            .decoderConfigured(width: width, height: height, frameRate: frameRate, codec: codec.rawValue)
        case .audioStarted(let channelCount, let sampleRate, let samplesPerFrame):
            .audioStarted(sampleRate: sampleRate, channels: channelCount, samplesPerFrame: samplesPerFrame)
        case .audioStopped:
            .audioStopped
        }
    }
}
