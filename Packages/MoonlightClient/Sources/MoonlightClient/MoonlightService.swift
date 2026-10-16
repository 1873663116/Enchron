import CMoonlightCore
import Foundation
import MoonlightBridge

public final class MoonlightService: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "app.enchron.moonlight.control")

    public static func configure(storageDirectory: String, deviceName: String) {
        MLCSetDeviceName(deviceName)
        MLCCryptoManager.setStorageDirectory(storageDirectory)
        MLCCryptoManager.generateKeyPairUsingSSL()
    }

    public init() {}

    public func fetchServerInfo(
        address: MoonlightHostAddress,
        serverCert: Data?
    ) async throws -> MoonlightServerInfo {
        try await run {
            let summary = try Self.serverInfo(address: address, serverCert: serverCert)
            return summary.info
        }
    }

    public func fetchApplications(
        address: MoonlightHostAddress,
        serverCert: Data?
    ) async throws -> [MoonlightApplication] {
        try await run {
            let manager = try Self.manager(address: address, serverCert: serverCert)
            let response = MLCAppListResponse()
            let request = MLCHttpRequest()
            request.response = response
            request.request = manager.newAppListRequest()
            guard request.request != nil else {
                throw MoonlightClientError.unreachable("applist request could not be built")
            }
            manager.executeRequestSynchronously(request)
            guard response.isStatusOk() else {
                throw MoonlightClientError.unreachable(
                    "applist status=\(response.statusCode) \(response.statusMessage ?? "")"
                )
            }
            let records = (response.getAppList() ?? []).compactMap { $0 as? MLCAppRecord }
            return records.compactMap { record in
                guard let id = record.id, let name = record.name else { return nil }
                return MoonlightApplication(id: id, name: name, hdrSupported: record.hdrSupported)
            }
            .sorted { $0.name < $1.name }
        }
    }

    public func fetchArtwork(
        address: MoonlightHostAddress,
        serverCert: Data?,
        appID: String
    ) async throws -> Data {
        try await run {
            let manager = try Self.manager(address: address, serverCert: serverCert)
            let response = MLCHttpResponse()
            let request = MLCHttpRequest()
            request.response = response
            request.request = manager.newAppAssetRequest(withAppId: appID)
            guard request.request != nil else {
                throw MoonlightClientError.unreachable("appasset request could not be built")
            }
            manager.executeRequestSynchronously(request)
            guard response.isStatusOk(), let data = response.data, !data.isEmpty else {
                throw MoonlightClientError.unreachable("appasset unavailable")
            }
            return data
        }
    }

    public func quitApplication(
        address: MoonlightHostAddress,
        serverCert: Data?
    ) async throws {
        try await run {
            let manager = try Self.manager(address: address, serverCert: serverCert)
            let response = MLCHttpResponse()
            let request = MLCHttpRequest()
            request.response = response
            request.request = manager.newQuitAppRequest()
            guard request.request != nil else {
                throw MoonlightClientError.unreachable("cancel request could not be built")
            }
            manager.executeRequestSynchronously(request)
            guard response.isStatusOk() else {
                throw MoonlightClientError.unreachable(
                    "cancel status=\(response.statusCode) \(response.statusMessage ?? "")"
                )
            }
        }
    }

    public func beginPairing(
        address: MoonlightHostAddress,
        serverCert: Data?
    ) async throws -> MoonlightPairingSession {
        try await run {
            MLCCryptoManager.generateKeyPairUsingSSL()
            guard let clientCert = MLCCryptoManager.readCertFromFile() else {
                throw MoonlightClientError.upstream("client certificate could not be generated")
            }
            let manager = try Self.manager(address: address, serverCert: serverCert)
            return MoonlightPairingSession(httpManager: manager, clientCert: clientCert)
        }
    }

    public func startSession(
        _ request: MoonlightStreamRequest,
        preference: MoonlightLaunchPreference = .automatic
    ) async throws -> MoonlightStreamSession {
        try await run {
            let summary = try Self.serverInfo(address: request.address, serverCert: request.serverCert)
            guard summary.info.pairStatus == 1 else {
                throw MoonlightClientError.notPaired
            }

            let busy = summary.info.state.hasSuffix("_SERVER_BUSY")
            let resume: Bool
            switch preference {
            case .automatic, .launchOnly:
                resume = busy && preference != .launchOnly
            case .resumeOnly:
                resume = true
            }
            if preference == .resumeOnly, !busy {
                throw MoonlightClientError.hostBusy("no existing session to resume")
            }

            let manager = try Self.manager(address: request.address, serverCert: request.serverCert)
            let config = MLCStreamConfiguration()
            config.host = request.address.addressPortString
            config.appID = request.appID
            config.appName = request.appName
            config.appVersion = summary.info.appVersion
            config.gfeVersion = summary.info.gfeVersion
            config.serverCodecModeSupport = Int32(bitPattern: summary.info.serverCodecModeSupport)
            config.width = Int32(request.width)
            config.height = Int32(request.height)
            config.frameRate = Int32(request.frameRate)
            config.bitRate = Int32(request.bitrateKbps)
            config.audioConfiguration = Self.stereoAudioConfiguration
            config.supportedVideoFormats = Self.supportedVideoFormats(
                codec: request.codec,
                hdrEnabled: request.hdrEnabled
            )
            config.riKey = MLCUtils.randomBytes(16)
            config.riKeyId = Int32(bitPattern: arc4random())
            config.gamepadMask = 0
            config.optimizeGameSettings = false
            config.playAudioOnPC = false
            config.swapABXYButtons = false
            config.multiController = false
            config.useFramePacing = false
            config.serverCert = request.serverCert

            let verb = resume ? "resume" : "launch"
            let response = MLCHttpResponse()
            guard let urlRequest = manager.newLaunchOrResumeRequest(verb, config: config) else {
                throw MoonlightClientError.unreachable("\(verb) request could not be built")
            }
            let httpRequest = MLCHttpRequest()
            httpRequest.response = response
            httpRequest.request = urlRequest
            manager.executeRequestSynchronously(httpRequest)
            guard response.isStatusOk() else {
                throw MoonlightClientError.launchRejected(
                    "\(verb) status=\(response.statusCode) \(response.statusMessage ?? "")"
                )
            }
            let marker = resume ? response.getStringTag("resume") : response.getStringTag("gamesession")
            guard let marker, marker != "0" else {
                throw MoonlightClientError.launchRejected("host did not accept \(verb)")
            }
            guard let sessionUrl = response.getStringTag("sessionUrl0"), !sessionUrl.isEmpty else {
                throw MoonlightClientError.launchRejected("\(verb) response carried no sessionUrl0")
            }
            config.rtspSessionUrl = Self.rewrittenRTSPUrl(sessionUrl, address: request.address)

            return MoonlightStreamSession(
                config: config,
                codec: request.codec,
                fallbackWidth: request.width,
                fallbackHeight: request.height,
                frameRate: request.frameRate
            )
        }
    }

    // MARK: - internals

    private func run<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static let stereoAudioConfiguration: Int32 = (0x3 << 16) | (2 << 8) | 0xCA

    static func supportedVideoFormats(codec: MoonlightVideoCodec, hdrEnabled: Bool) -> Int32 {
        let h264 = Int32(VIDEO_FORMAT_H264)
        let h265 = Int32(VIDEO_FORMAT_H265)
        let h265Main10 = Int32(VIDEO_FORMAT_H265_MAIN10)
        switch codec {
        case .h264:
            return h264
        case .hevc:
            return hdrEnabled ? (h265 | h265Main10) : h265
        case .av1:
            return Int32(VIDEO_FORMAT_AV1_MAIN8)
        case .auto:
            let base = h265 | h264
            return hdrEnabled ? (base | h265Main10) : base
        }
    }

    static func rewrittenRTSPUrl(_ urlString: String, address: MoonlightHostAddress) -> String {
        guard address.portOffset != 0 else { return urlString }
        let port = "\(address.portBase + 21)"
        guard var components = URLComponents(string: urlString) else { return urlString }
        components.port = Int(port)
        return components.string ?? urlString
    }

    static func manager(address: MoonlightHostAddress, serverCert: Data?) throws -> MLCHttpManager {
        guard let manager = MLCHttpManager(
            address: address.addressPortString,
            httpsPort: 0,
            serverCert: serverCert
        ) else {
            throw MoonlightClientError.unreachable("HTTP manager could not be created")
        }
        manager.setServerCert(serverCert)
        return manager
    }

    struct ServerInfoSummary {
        var info: MoonlightServerInfo
        var hostRecord: MLCHostRecord
    }

    static func serverInfo(
        address: MoonlightHostAddress,
        serverCert: Data?
    ) throws -> ServerInfoSummary {
        let manager = try manager(address: address, serverCert: serverCert)
        let response = MLCServerInfoResponse()
        let request = MLCHttpRequest()
        request.response = response
        request.request = manager.newServerInfoRequest(false)
        request.fallbackError = 401
        request.fallbackRequest = manager.newHttpServerInfoRequest(false)
        guard request.request != nil else {
            throw MoonlightClientError.unreachable("serverinfo request could not be built")
        }
        manager.executeRequestSynchronously(request)
        guard response.isStatusOk() else {
            throw MoonlightClientError.unreachable(
                "serverinfo status=\(response.statusCode) \(response.statusMessage ?? "")"
            )
        }

        let record = MLCHostRecord()
        response.populateHost(record)

        let offset = address.portOffset
        let httpsPort = offset == 0
            ? record.httpsPort
            : UInt16(clamping: Int(record.httpsPort) + offset)

        let info = MoonlightServerInfo(
            name: record.name ?? "",
            uniqueID: record.uuid ?? "",
            pairStatus: Int(response.getStringTag("PairStatus") ?? "0") ?? 0,
            httpsPort: httpsPort,
            appVersion: response.getStringTag("appversion") ?? "",
            gfeVersion: response.getStringTag("GfeVersion"),
            serverCodecModeSupport: UInt32(bitPattern: record.serverCodecModeSupport),
            state: response.getStringTag("state") ?? "",
            currentGame: record.currentGame
        )
        return ServerInfoSummary(info: info, hostRecord: record)
    }
}

public final class MoonlightPairingSession: @unchecked Sendable {
    public let pairingID = UUID()
    private let callback: PairingCallbackBox
    private let pairManager: MLCPairManager
    private let queue = OperationQueue()

    init(httpManager: MLCHttpManager, clientCert: Data) {
        let callback = PairingCallbackBox()
        self.callback = callback
        self.pairManager = MLCPairManager(
            manager: httpManager,
            clientCert: clientCert,
            callback: callback
        )
        queue.maxConcurrentOperationCount = 1
        queue.addOperation(pairManager)
    }

    public func pin() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            callback.awaitPin { result in
                continuation.resume(with: result)
            }
        }
    }

    public func outcome() async throws -> MoonlightPairingOutcome {
        try await withCheckedThrowingContinuation { continuation in
            callback.awaitOutcome { result in
                continuation.resume(with: result)
            }
        }
    }

    public func cancel() {
        callback.cancel()
        pairManager.cancel()
    }
}

private final class PairingCallbackBox: NSObject, MLCPairCallback, @unchecked Sendable {
    private let lock = NSLock()
    private var pinValue: String?
    private var outcomeValue: MoonlightPairingOutcome?
    private var pinWaiters: [(Result<String, Error>) -> Void] = []
    private var outcomeWaiters: [(Result<MoonlightPairingOutcome, Error>) -> Void] = []

    func awaitPin(_ handler: @escaping (Result<String, Error>) -> Void) {
        lock.lock()
        if let pinValue {
            lock.unlock()
            handler(.success(pinValue))
            return
        }
        pinWaiters.append(handler)
        lock.unlock()
    }

    func awaitOutcome(_ handler: @escaping (Result<MoonlightPairingOutcome, Error>) -> Void) {
        lock.lock()
        if let outcomeValue {
            lock.unlock()
            handler(.success(outcomeValue))
            return
        }
        outcomeWaiters.append(handler)
        lock.unlock()
    }

    func cancel() {
        let waiters: [(Result<MoonlightPairingOutcome, Error>) -> Void]
        lock.lock()
        outcomeValue = .cancelled
        waiters = outcomeWaiters
        outcomeWaiters = []
        lock.unlock()
        for waiter in waiters {
            waiter(.success(.cancelled))
        }
    }

    func startPairing(_ PIN: String) {
        let waiters: [(Result<String, Error>) -> Void]
        lock.lock()
        pinValue = PIN
        waiters = pinWaiters
        pinWaiters = []
        lock.unlock()
        for waiter in waiters {
            waiter(.success(PIN))
        }
    }

    func pairSuccessful(_ serverCert: Data) {
        finish(.paired(serverCert: serverCert))
    }

    func pairFailed(_ message: String) {
        finish(.failed(message))
    }

    func alreadyPaired() {
        finish(.alreadyPaired)
    }

    private func finish(_ outcome: MoonlightPairingOutcome) {
        let waiters: [(Result<MoonlightPairingOutcome, Error>) -> Void]
        lock.lock()
        guard outcomeValue == nil else {
            lock.unlock()
            return
        }
        outcomeValue = outcome
        waiters = outcomeWaiters
        outcomeWaiters = []
        lock.unlock()
        for waiter in waiters {
            waiter(.success(outcome))
        }
    }
}
