import Foundation
import CoreMedia
import VideoToolbox
import CMoonlightCore
import MoonlightBridge

// MARK: - Output helpers

func logLine(_ message: String) {
    print(message)
    fflush(stdout)
}

func failLine(_ message: String) -> Never {
    FileHandle.standardError.write(("[probe] " + message + "\n").data(using: .utf8)!)
    exit(2)
}

// MARK: - Options

struct Options {
    var host = "127.0.0.1:47989"
    var appID = ""
    var width: Int32 = 1280
    var height: Int32 = 720
    var fps: Int32 = 60
    var bitrate: Int32 = 20000
    var codec = "h264"
    var seconds: Double = 15
    var keepRunning = false
    var workDir: String?
    var mouseX: Float = 0.25
    var mouseY: Float = 0.25
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 2
    while index < arguments.count {
        let key = arguments[index]
        let value = index + 1 < arguments.count ? arguments[index + 1] : nil
        switch key {
        case "--host": options.host = value ?? options.host; index += 2
        case "--app": options.appID = value ?? ""; index += 2
        case "--width": options.width = Int32(value ?? "") ?? options.width; index += 2
        case "--height": options.height = Int32(value ?? "") ?? options.height; index += 2
        case "--fps": options.fps = Int32(value ?? "") ?? options.fps; index += 2
        case "--bitrate": options.bitrate = Int32(value ?? "") ?? options.bitrate; index += 2
        case "--codec": options.codec = value ?? options.codec; index += 2
        case "--seconds": options.seconds = Double(value ?? "") ?? options.seconds; index += 2
        case "--work-dir": options.workDir = value; index += 2
        case "--mouse-x": options.mouseX = Float(value ?? "") ?? options.mouseX; index += 2
        case "--mouse-y": options.mouseY = Float(value ?? "") ?? options.mouseY; index += 2
        case "--keep-running": options.keepRunning = true; index += 1
        default: failLine("unknown option \(key)")
        }
    }
    return options
}

// MARK: - Control plane (MoonlightBridge HTTP/crypto stack)

// The control probe's work directory holds the pinned server certificate and the
// client identity that pairing produced.
let defaultWorkDir = "/tmp/mlc-control-probe"

struct HostSessionInfo {
    var pairStatus: String
    var appVersion: String
    var gfeVersion: String?
    var state: String
    var codecModeSupport: Int32
}

enum ControlPlaneError: Error {
    case request(String)
}

func makeRequest(_ response: MLCResponse, _ urlRequest: URLRequest?) -> MLCHttpRequest? {
    guard let urlRequest else { return nil }
    let request = MLCHttpRequest()
    request.request = urlRequest
    request.response = response
    return request
}

final class ControlPlane {
    let host: String
    let workDir: String
    let pinnedCert: Data?

    init(host: String, workDir: String?) {
        self.host = host
        self.workDir = workDir ?? defaultWorkDir
        try? FileManager.default.createDirectory(atPath: self.workDir, withIntermediateDirectories: true)
        MLCCryptoManager.setStorageDirectory(self.workDir)
        MLCCryptoManager.generateKeyPairUsingSSL()
        self.pinnedCert = FileManager.default.contents(atPath: (self.workDir as NSString).appendingPathComponent("server.crt"))
    }

    var transportDescription: String {
        pinnedCert != nil ? "https-pinned" : "http"
    }

    private func manager() -> MLCHttpManager {
        guard let manager = MLCHttpManager(address: host, httpsPort: 0, serverCert: pinnedCert) else {
            failLine("could not create the HTTP manager")
        }
        return manager
    }

    func serverInfo() throws -> HostSessionInfo {
        let response = MLCServerInfoResponse()
        let httpManager = manager()
        guard let request = makeRequest(response, httpManager.newServerInfoRequest(false)) else {
            throw ControlPlaneError.request("no serverinfo URL")
        }
        httpManager.executeRequestSynchronously(request)

        guard response.isStatusOk() else {
            throw ControlPlaneError.request("serverinfo status=\(response.statusCode) message=\(response.statusMessage ?? "")")
        }

        let hostRecord = MLCHostRecord()
        response.populateHost(hostRecord)
        return HostSessionInfo(pairStatus: response.getStringTag("PairStatus") ?? "",
                               appVersion: response.getStringTag("appversion") ?? "",
                               gfeVersion: response.getStringTag("GfeVersion"),
                               state: response.getStringTag("state") ?? "",
                               codecModeSupport: Int32(hostRecord.serverCodecModeSupport))
    }

    func appList() throws -> [(id: String, name: String)] {
        let response = MLCAppListResponse()
        let httpManager = manager()
        guard let request = makeRequest(response, httpManager.newAppListRequest()) else {
            throw ControlPlaneError.request("no applist URL")
        }
        httpManager.executeRequestSynchronously(request)

        guard response.isStatusOk() else {
            throw ControlPlaneError.request("applist status=\(response.statusCode) message=\(response.statusMessage ?? "")")
        }

        let records = (response.getAppList() ?? []).compactMap { $0 as? MLCAppRecord }
        return records.compactMap { record in
            guard let id = record.id, let name = record.name else { return nil }
            return (id: id, name: name)
        }
    }

    func launch(resume: Bool, config: MLCStreamConfiguration) throws -> String {
        let verb = resume ? "resume" : "launch"
        let response = MLCHttpResponse()
        let httpManager = manager()
        guard let request = makeRequest(response, httpManager.newLaunchOrResumeRequest(verb, config: config)) else {
            throw ControlPlaneError.request("no \(verb) URL")
        }
        httpManager.executeRequestSynchronously(request)

        guard response.isStatusOk() else {
            throw ControlPlaneError.request("\(verb) status=\(response.statusCode) message=\(response.statusMessage ?? "")")
        }

        let marker = resume ? response.getStringTag("resume") : response.getStringTag("gamesession")
        guard let marker, marker != "0" else {
            throw ControlPlaneError.request("host did not accept \(verb)")
        }

        guard let sessionUrl = response.getStringTag("sessionUrl0"), !sessionUrl.isEmpty else {
            throw ControlPlaneError.request("\(verb) response carried no sessionUrl0")
        }
        return sessionUrl
    }

    func quitApp() throws {
        let response = MLCHttpResponse()
        let httpManager = manager()
        guard let request = makeRequest(response, httpManager.newQuitAppRequest()) else {
            throw ControlPlaneError.request("no quit URL")
        }
        httpManager.executeRequestSynchronously(request)

        guard response.isStatusOk() else {
            throw ControlPlaneError.request("quitapp status=\(response.statusCode) message=\(response.statusMessage ?? "")")
        }
    }
}

// MARK: - Session consumer

struct SessionSnapshot {
    var samples = 0
    var decoded = 0
    var decodeErrors = 0
    var submitErrors = 0
    var audioFrames = 0
    var audioBytes = 0
    var audioSampleRate: UInt32 = 0
    var audioChannels: UInt32 = 0
    var stages: [String] = []
    var stageFailures: [String] = []
    var contentShown = false
    var terminated = false
    var terminationError: Int32 = 0
    var formatOK = false
    var formatName = "none"
    var queueDepth: Int32 = 0
    var videoWidth: Int32 = 0
    var videoHeight: Int32 = 0
}

final class SessionConsumer: NSObject, MLCConnectionDelegate, MLCVideoSampleBuilderDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var state = SessionSnapshot()
    private let codecLabel: String
    private let decodeSampleLimit: Int
    private var vtSession: VTDecompressionSession?

    init(codecLabel: String, decodeSampleLimit: Int = 30) {
        self.codecLabel = codecLabel
        self.decodeSampleLimit = decodeSampleLimit
        super.init()
    }

    // MARK: MLCConnectionDelegate

    func connectionStarted() {
        logLine("stage=connectionStarted")
    }

    func connectionTerminated(_ errorCode: Int32) {
        lock.lock(); state.terminated = true; state.terminationError = errorCode; lock.unlock()
        logLine("stage=connectionTerminated error=\(errorCode)")
    }

    func stageStarting(_ stageName: UnsafePointer<CChar>!) {
        let name = String(cString: stageName)
        lock.lock(); state.stages.append("start:" + name); lock.unlock()
        logLine("stage=stageStarting name=\(name)")
    }

    func stageComplete(_ stageName: UnsafePointer<CChar>!) {
        let name = String(cString: stageName)
        lock.lock(); state.stages.append("complete:" + name); lock.unlock()
        logLine("stage=stageComplete name=\(name)")
    }

    func stageFailed(_ stageName: UnsafePointer<CChar>!, withError errorCode: Int32, portTestFlags: Int32) {
        let name = String(cString: stageName)
        lock.lock(); state.stages.append("failed:" + name); state.stageFailures.append("\(name):\(errorCode)"); lock.unlock()
        logLine("stage=stageFailed name=\(name) error=\(errorCode) portTestFlags=\(portTestFlags)")
    }

    func connectionStatusUpdate(_ status: Int32) {
        logLine("stage=connectionStatusUpdate status=\(status)")
    }

    func setHdrMode(_ enabled: Bool) {
        logLine("stage=setHdrMode enabled=\(enabled)")
    }

    func videoContentShown() {
        lock.lock(); state.contentShown = true; lock.unlock()
        logLine("stage=videoContentShown")
    }

    // MARK: MLCVideoSampleBuilderDelegate

    func videoSampleBuilder(_ builder: MLCVideoSampleBuilder,
                            didProduceSample sampleBuffer: CMSampleBuffer,
                            frameType: Int32,
                            presentationTimeUs: UInt64) {
        lock.lock()
        state.samples += 1
        let index = state.samples
        let wantsDecode = index <= decodeSampleLimit
        lock.unlock()

        if vtSession == nil {
            createDecodeSession(from: sampleBuffer)
        }

        guard wantsDecode, let session = vtSession else { return }

        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sampleBuffer, flags: [], infoFlagsOut: &infoFlags) { [weak self] status, _, imageBuffer, _, _ in
            guard let self else { return }
            self.lock.lock()
            if status == noErr && imageBuffer != nil {
                self.state.decoded += 1
            }
            else if status != noErr {
                self.state.decodeErrors += 1
            }
            self.lock.unlock()
        }
        if status != noErr {
            lock.lock(); state.submitErrors += 1; lock.unlock()
            logLine("decode-submit-failed index=\(index) status=\(status)")
        }
    }

    private func createDecodeSession(from sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            logLine("FORMAT-FAIL sample carries no format description")
            return
        }

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                  formatDescription: formatDescription,
                                                  decoderSpecification: nil,
                                                  imageBufferAttributes: nil,
                                                  outputCallback: nil,
                                                  decompressionSessionOut: &session)
        let fourCC = fourCCString(CMFormatDescriptionGetMediaSubType(formatDescription))
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)

        lock.lock()
        state.formatName = fourCC
        state.formatOK = status == noErr
        state.videoWidth = dimensions.width
        state.videoHeight = dimensions.height
        lock.unlock()

        if status == noErr, let session {
            vtSession = session
            logLine("\(codecLabel)-OK format=\(fourCC) dimensions=\(dimensions)")
        }
        else {
            logLine("\(codecLabel)-FAIL format=\(fourCC) vtStatus=\(status)")
        }
    }

    func shutDownDecodeSession() {
        if let session = vtSession {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
            vtSession = nil
        }
    }

    // MARK: Audio

    func attachAudio(to connection: MLCConnection) {
        connection.audioStarted = {
            logLine("stage=audioStarted")
        }
        connection.audioStopped = {
            logLine("stage=audioStopped")
        }
        connection.audioFrameHandler = { [weak self] pcm, channelCount, sampleRate, frameCount in
            guard let self, let pcm else { return }
            self.lock.lock()
            self.state.audioFrames += 1
            self.state.audioBytes += pcm.count
            self.state.audioSampleRate = sampleRate
            self.state.audioChannels = channelCount
            self.lock.unlock()
        }
    }

    // MARK: Snapshot

    func snapshot() -> SessionSnapshot {
        lock.lock()
        defer {
            state.queueDepth = LiGetPendingVideoFrames()
            lock.unlock()
        }
        return state
    }

    func statusLine() -> String {
        let snapshot = self.snapshot()
        return "samples=\(snapshot.samples) decoded=\(snapshot.decoded) audioFrames=\(snapshot.audioFrames) queueDepth=\(snapshot.queueDepth)"
    }
}

func fourCCString(_ code: FourCharCode) -> String {
    let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
}

// MARK: - Session driving

// SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION for stereo: channel mask 0x3, 2 channels.
let stereoAudioConfiguration: Int32 = (0x3 << 16) | (2 << 8) | 0xCA

func supportedVideoFormat(for codec: String) -> Int32 {
    switch codec {
    case "h264": return VIDEO_FORMAT_H264
    case "hevc": return VIDEO_FORMAT_H265
    default: failLine("unsupported codec \(codec)")
    }
}

struct SessionHandle {
    var connection: MLCConnection
    var consumer: SessionConsumer
    var resumed: Bool
    var appName: String
}

func startSession(options: Options, control: ControlPlane) throws -> SessionHandle {
    let summary = try control.serverInfo()
    logLine("serverinfo transport=\(control.transportDescription) PairStatus=\(summary.pairStatus) appversion=\(summary.appVersion) state=\(summary.state) codecModeSupport=\(summary.codecModeSupport)")
    guard summary.pairStatus == "1" else {
        if control.pinnedCert == nil {
            failLine("host is not reachable as paired over plain HTTP: no pinned server certificate in \(control.workDir); point --work-dir at the directory that holds server.crt (default \(defaultWorkDir))")
        }
        failLine("host is not paired (PairStatus=\(summary.pairStatus)); pair the host before running the session probe")
    }

    let apps = try control.appList()
    guard let app = apps.first(where: { $0.id == options.appID }) else {
        failLine("app \(options.appID) missing from applist (\(apps.map { $0.id }.joined(separator: ",")))")
    }
    logLine("applist resolved app=\(app.id) name=\(app.name)")

    let config = MLCStreamConfiguration()
    config.host = options.host
    config.appID = options.appID
    config.appName = app.name
    config.appVersion = summary.appVersion
    config.gfeVersion = summary.gfeVersion
    config.serverCodecModeSupport = summary.codecModeSupport
    config.width = options.width
    config.height = options.height
    config.frameRate = options.fps
    config.bitRate = options.bitrate
    config.audioConfiguration = stereoAudioConfiguration
    config.supportedVideoFormats = supportedVideoFormat(for: options.codec)
    config.riKey = MLCUtils.randomBytes(16)
    config.riKeyId = Int32(bitPattern: arc4random())
    config.gamepadMask = 0
    config.optimizeGameSettings = false
    config.playAudioOnPC = true
    config.swapABXYButtons = false
    config.multiController = false
    config.useFramePacing = false

    let resumed = summary.state.hasSuffix("_SERVER_BUSY")
    logLine("stage=\(resumed ? "resume" : "launch") hostState=\(summary.state)")
    config.rtspSessionUrl = try control.launch(resume: resumed, config: config)
    logLine("stage=\(resumed ? "resume" : "launch") rtspSessionUrl=\(config.rtspSessionUrl ?? "nil")")

    let consumer = SessionConsumer(codecLabel: options.codec == "hevc" ? "HEVC" : "H264")
    guard let connection = MLCConnection(config: config, delegate: consumer) else {
        failLine("MLCConnection init returned nil")
    }
    consumer.attachAudio(to: connection)
    connection.videoConsumer = consumer
    return SessionHandle(connection: connection, consumer: consumer, resumed: resumed, appName: app.name)
}

func startConnectionOffMainThread(_ handle: SessionHandle) {
    let connection = handle.connection
    Thread {
        connection.start()
        logLine("stage=connectionThreadExited")
    }.start()
}

func writeReport(_ payload: [String: Any], workDir: String?) {
    guard let workDir else { return }
    let directory = URL(fileURLWithPath: workDir)
    let url = directory.appendingPathComponent("session-probe.json")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: url)
        logLine("report=\(url.path)")
    }
}

func reportFinal(handle: SessionHandle, options: Options) -> Int32 {
    let snapshot = handle.consumer.snapshot()
    let videoOK = snapshot.samples >= 30 && snapshot.decoded >= 25
    let stagesOK = snapshot.stages.contains(where: { $0.hasPrefix("start:") }) && snapshot.stages.contains(where: { $0.hasPrefix("complete:") })
    let expectedFormat = options.codec == "hevc" ? "HEVC" : "H264"

    logLine(videoOK
        ? "VIDEO-OK samples=\(snapshot.samples) decoded=\(snapshot.decoded)"
        : "VIDEO-FAIL samples=\(snapshot.samples) decoded=\(snapshot.decoded) decodeErrors=\(snapshot.decodeErrors) submitErrors=\(snapshot.submitErrors)")
    logLine(snapshot.audioFrames > 0
        ? "AUDIO-OK audioFrames=\(snapshot.audioFrames) bytes=\(snapshot.audioBytes) rate=\(snapshot.audioSampleRate) channels=\(snapshot.audioChannels)"
        : "AUDIO-FAIL audioFrames=0 (host sent no audio or the Opus decoder never ran)")
    logLine(stagesOK ? "STAGES-OK transitions=\(snapshot.stages.count)" : "STAGES-FAIL transitions=\(snapshot.stages.count)")
    logLine(snapshot.formatOK ? "\(expectedFormat)-OK format=\(snapshot.formatName)" : "\(expectedFormat)-FAIL format=\(snapshot.formatName)")
    logLine("CONTENT-SHOWN=\(snapshot.contentShown) TERMINATED=\(snapshot.terminated) TERMINATION-ERROR=\(snapshot.terminationError) RESUMED=\(handle.resumed) CODEC=\(handle.connection.getActiveCodecName() ?? "unknown")")
    if !snapshot.stageFailures.isEmpty {
        logLine("STAGE-FAILURES=\(snapshot.stageFailures.joined(separator: ","))")
    }

    writeReport([
        "host": options.host,
        "app": options.appID,
        "appName": handle.appName,
        "codec": options.codec,
        "resumed": handle.resumed,
        "samples": snapshot.samples,
        "decoded": snapshot.decoded,
        "decodeErrors": snapshot.decodeErrors,
        "submitErrors": snapshot.submitErrors,
        "audioFrames": snapshot.audioFrames,
        "audioBytes": snapshot.audioBytes,
        "formatOK": snapshot.formatOK,
        "format": snapshot.formatName,
        "contentShown": snapshot.contentShown,
        "stages": snapshot.stages,
        "stageFailures": snapshot.stageFailures,
        "videoOK": videoOK,
        "stagesOK": stagesOK,
        "negotiatedCodec": handle.connection.getActiveCodecName() ?? "unknown",
    ], workDir: options.workDir)

    return (videoOK && stagesOK) ? 0 : 1
}

func quitAppUnlessKeptRunning(options: Options, control: ControlPlane) {
    guard !options.keepRunning else {
        logLine("stage=quitapp skipped (--keep-running)")
        return
    }
    do {
        try control.quitApp()
        logLine("stage=quitapp sent")
    }
    catch {
        logLine("stage=quitapp failed error=\(error)")
    }
}

// MARK: - Verbs

func runStream(options: Options, control: ControlPlane) throws -> Int32 {
    let handle = try startSession(options: options, control: control)
    startConnectionOffMainThread(handle)

    let deadline = Date().addingTimeInterval(options.seconds)
    var elapsed = 0.0
    while Date() < deadline {
        if handle.consumer.snapshot().terminated { break }
        Thread.sleep(forTimeInterval: 1)
        elapsed += 1
        var rtt: UInt32 = 0
        var variance: UInt32 = 0
        let rttText = MLCInputSender.estimatedRttMs(&rtt, variance: &variance) ? "\(rtt)/\(variance)" : "unavailable"
        logLine("[\(Int(elapsed))s] \(handle.consumer.statusLine()) rtt=\(rttText) codec=\(handle.connection.getActiveCodecName() ?? "unknown")")
    }

    let exitCode = reportFinal(handle: handle, options: options)

    handle.consumer.shutDownDecodeSession()
    MLCInputSender.releaseAllPressedKeysAndButtons()
    handle.connection.terminate()
    Thread.sleep(forTimeInterval: 2)
    quitAppUnlessKeptRunning(options: options, control: control)
    return exitCode
}

func hidUsage(forASCII ascii: UInt8) -> Int? {
    if ascii >= 0x61 && ascii <= 0x7A { return Int(ascii - 0x61) + 0x04 }
    if ascii >= 0x31 && ascii <= 0x39 { return Int(ascii - 0x31) + 0x1E }
    if ascii == 0x30 { return 0x27 }
    return nil
}

func runInput(options: Options, control: ControlPlane) throws -> Int32 {
    let handle = try startSession(options: options, control: control)
    startConnectionOffMainThread(handle)

    let text = "ency" + String(format: "%04x", arc4random_uniform(0x10000))
    Thread.sleep(forTimeInterval: 3)

    let x: Float = options.mouseX
    let y: Float = options.mouseY
    let negotiated = handle.consumer.snapshot()
    let referenceWidth = negotiated.videoWidth > 0 ? Int16(negotiated.videoWidth) : Int16(options.width)
    let referenceHeight = negotiated.videoHeight > 0 ? Int16(negotiated.videoHeight) : Int16(options.height)
    MLCInputSender.sendMousePositionNormalizedX(x, y: y, referenceWidth: referenceWidth, referenceHeight: referenceHeight)
    Thread.sleep(forTimeInterval: 0.3)

    for character in text.utf8 {
        guard let usage = hidUsage(forASCII: character) else { continue }
        MLCInputSender.sendKey(withHIDUsage: usage, down: true, modifierFlags: 0)
        Thread.sleep(forTimeInterval: 0.04)
        MLCInputSender.sendKey(withHIDUsage: usage, down: false, modifierFlags: 0)
        Thread.sleep(forTimeInterval: 0.04)
    }

    Thread.sleep(forTimeInterval: 0.3)
    MLCInputSender.sendScrollVerticalClicks(1)
    Thread.sleep(forTimeInterval: 0.5)

    logLine("INPUT-SENT \(text) \(x) \(y) reference=\(referenceWidth)x\(referenceHeight)")
    logLine("INPUT-STATE \(handle.consumer.statusLine())")

    Thread.sleep(forTimeInterval: 2)
    MLCInputSender.releaseAllPressedKeysAndButtons()
    handle.consumer.shutDownDecodeSession()
    handle.connection.terminate()
    Thread.sleep(forTimeInterval: 2)

    writeReport([
        "host": options.host,
        "app": options.appID,
        "typed": text,
        "mouse": ["normalizedX": x, "normalizedY": y],
        "scroll": 1,
        "samples": handle.consumer.snapshot().samples,
    ], workDir: options.workDir)

    quitAppUnlessKeptRunning(options: options, control: control)
    return 0
}

func runServerInfo(options: Options, control: ControlPlane) throws -> Int32 {
    let summary = try control.serverInfo()
    logLine("serverinfo transport=\(control.transportDescription) PairStatus=\(summary.pairStatus) appversion=\(summary.appVersion) gfeVersion=\(summary.gfeVersion ?? "nil") state=\(summary.state) codecModeSupport=\(summary.codecModeSupport)")
    return summary.pairStatus == "1" ? 0 : 3
}

func runAppList(options: Options, control: ControlPlane) throws -> Int32 {
    for app in try control.appList() {
        logLine("app id=\(app.id) name=\(app.name)")
    }
    return 0
}

func runQuitApp(options: Options, control: ControlPlane) throws -> Int32 {
    try control.quitApp()
    logLine("quitapp sent")
    return 0
}

func showUsage() -> Never {
    logLine("""
    usage:
      MoonlightSessionProbe stream     --host <addr:port> --app <appid> [--width N] [--height N] [--fps N] [--bitrate N] [--codec h264|hevc] [--seconds N] [--work-dir DIR] [--keep-running]
      MoonlightSessionProbe input      --host <addr:port> --app <appid> [--codec h264|hevc] [--mouse-x F] [--mouse-y F] [--work-dir DIR] [--keep-running]
      MoonlightSessionProbe applist    --host <addr:port>
      MoonlightSessionProbe serverinfo --host <addr:port>
      MoonlightSessionProbe quitapp    --host <addr:port>
    """)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { showUsage() }
let options = parseOptions(arguments)

do {
    let control = ControlPlane(host: options.host, workDir: options.workDir)
    let code: Int32
    switch arguments[1] {
    case "stream": code = try runStream(options: options, control: control)
    case "input": code = try runInput(options: options, control: control)
    case "applist": code = try runAppList(options: options, control: control)
    case "serverinfo": code = try runServerInfo(options: options, control: control)
    case "quitapp": code = try runQuitApp(options: options, control: control)
    default: showUsage()
    }
    exit(code)
}
catch let ControlPlaneError.request(message) {
    failLine("control plane request failed: \(message)")
}
catch {
    failLine("failure: \(error)")
}
