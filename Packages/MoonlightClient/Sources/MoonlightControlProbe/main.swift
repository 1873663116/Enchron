import CryptoKit
import Foundation
import MoonlightBridge


let defaultWorkDir = "/tmp/mlc-control-probe"
let defaultWebUIPort = 47990
let deviceName = "Enchron"

struct VerbOptions {
    let verb: String
    let values: [String: String]
    let flags: Set<String>

    func value(_ name: String) -> String? { values[name] }
    func isSet(_ name: String) -> Bool { flags.contains(name) }

    func require(_ name: String) -> String {
        guard let v = values[name] else {
            FileHandle.standardError.write("missing required option \(name)\n".data(using: .utf8)!)
            exit(2)
        }
        return v
    }
}

func parseArguments() -> VerbOptions {
    let argv = CommandLine.arguments
    guard argv.count >= 2 else {
        FileHandle.standardError.write("usage: MoonlightControlProbe <serverinfo|applist|pair|quitapp> --host <addr:port> [...]\n".data(using: .utf8)!)
        exit(2)
    }
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var i = 2
    while i < argv.count {
        let token = argv[i]
        guard token.hasPrefix("--") else {
            FileHandle.standardError.write("unexpected argument \(token)\n".data(using: .utf8)!)
            exit(2)
        }
        let key = String(token.dropFirst(2))
        if i + 1 < argv.count && !argv[i + 1].hasPrefix("--") {
            values[key] = argv[i + 1]
            i += 2
        } else {
            flags.insert(key)
            i += 1
        }
    }
    return VerbOptions(verb: argv[1], values: values, flags: flags)
}

func workDirectory(_ options: VerbOptions) -> String {
    let dir = options.value("work-dir") ?? defaultWorkDir
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

func serverCertPath(_ workDir: String) -> String {
    return (workDir as NSString).appendingPathComponent("server.crt")
}

func readServerCert(_ workDir: String) -> Data? {
    return FileManager.default.contents(atPath: serverCertPath(workDir))
}

func sha256(_ data: Data) -> String {
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func hostAddress(_ host: String) -> String {
    var address = host
    if address.hasPrefix("[") {
        if let end = address.firstIndex(of: "]") {
            address = String(address[address.index(after: address.startIndex)..<end])
        }
    } else if let colon = address.lastIndex(of: ":") {
        address = String(address[..<colon])
    }
    return address
}

final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class WebUIClient {
    let baseURL: URL
    let authorization: String
    private let session: URLSession

    init(address: String, port: Int, user: String, password: String) {
        baseURL = URL(string: "https://\(address):\(port)")!
        authorization = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
        session = URLSession(configuration: .ephemeral, delegate: InsecureTrustDelegate(), delegateQueue: nil)
    }

    private func perform(_ request: URLRequest) -> (Data?, Int, Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var body: Data?
        nonisolated(unsafe) var status = 0
        nonisolated(unsafe) var failure: Error?
        var request = request
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        session.dataTask(with: request) { data, response, error in
            body = data
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            failure = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return (body, status, failure)
    }

    func pendingPairings() -> [[String: Any]]? {
        let (data, status, _) = perform(URLRequest(url: baseURL.appendingPathComponent("/api/pin")))
        guard status == 200, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["pairings"] as? [[String: Any]]
    }

    func submitPin(pairingId: String, pin: String) -> (Bool, String) {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/pin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "pairing_id": pairingId,
            "pin": pin,
            "name": deviceName,
        ])
        let (data, status, error) = perform(request)
        if let error {
            return (false, "web UI request failed: \(error.localizedDescription)")
        }
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return (status == 200 && body.contains("\"status\":true"), "http=\(status) body=\(body)")
    }
}

func webUICredentials(_ options: VerbOptions) -> (String, String) {
    if let user = options.value("webui-user"), let password = options.value("webui-password") {
        return (user, password)
    }
    let environment = ProcessInfo.processInfo.environment
    let home = environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
    let path = (home as NSString).appendingPathComponent(".config/sunshine/enchron-webui-credentials.txt")
    var user: String?
    var password: String?
    if let text = try? String(contentsOfFile: path, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "user": user = value
            case "password": password = value
            default: break
            }
        }
    }
    guard let user, let password else {
        FileHandle.standardError.write("no web UI credentials: pass --webui-user/--webui-password or provide \(path)\n".data(using: .utf8)!)
        exit(2)
    }
    return (user, password)
}

func makeRequest(_ response: MLCResponse, _ urlRequest: URLRequest?) -> MLCHttpRequest? {
    guard let urlRequest else { return nil }
    let request = MLCHttpRequest()
    request.request = urlRequest
    request.response = response
    return request
}

enum PairOutcome {
    case success(Data)
    case failure(String)
}

final class PairCallback: NSObject, MLCPairCallback {
    let started = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _pin: String?
    private var _result: PairOutcome?
    private var _alreadyPaired = false

    var pin: String? {
        lock.lock(); defer { lock.unlock() }
        return _pin
    }
    var result: PairOutcome? {
        lock.lock(); defer { lock.unlock() }
        return _result
    }
    var hasAlreadyPaired: Bool {
        lock.lock(); defer { lock.unlock() }
        return _alreadyPaired
    }

    func startPairing(_ PIN: String) {
        lock.lock(); _pin = PIN; lock.unlock()
        started.signal()
    }
    func pairSuccessful(_ serverCert: Data) {
        lock.lock(); _result = .success(serverCert); lock.unlock()
        finished.signal()
    }
    func pairFailed(_ message: String) {
        lock.lock(); _result = .failure(message); lock.unlock()
        finished.signal()
    }
    func alreadyPaired() {
        lock.lock(); _alreadyPaired = true; lock.unlock()
        finished.signal()
    }
}

func runServerInfo(_ options: VerbOptions) {
    let host = options.require("host")
    let workDir = workDirectory(options)
    let pinnedCert = options.isSet("no-tls") ? nil : readServerCert(workDir)
    let manager = MLCHttpManager(address: host, httpsPort: 0, serverCert: pinnedCert)!

    let response = MLCServerInfoResponse()
    guard let request = makeRequest(response, manager.newServerInfoRequest(false)) else {
        print("FAIL serverinfo: no serverinfo URL")
        exit(1)
    }
    manager.executeRequestSynchronously(request)

    let hostRecord = MLCHostRecord()
    response.populateHost(hostRecord)

    print("transport=\(pinnedCert != nil ? "https-pinned" : "http")")
    if let pinnedCert {
        print("pinned-cert-sha256=\(sha256(pinnedCert))")
    }
    print("status=\(response.statusCode) message=\(response.statusMessage ?? "")")
    print("name=\(response.getStringTag("hostname") ?? "")")
    print("uniqueid=\(response.getStringTag("uniqueid") ?? "")")
    print("PairStatus=\(response.getStringTag("PairStatus") ?? "")")
    print("HttpsPort=\(response.getStringTag("HttpsPort") ?? "")")
    print("appversion=\(response.getStringTag("appversion") ?? "")")
    print("state=\(response.getStringTag("state") ?? "")")
    print("host.pairState=\(hostRecord.pairState.rawValue) host.httpsPort=\(hostRecord.httpsPort)")
    if response.statusCode != 200 {
        exit(1)
    }
}

func runAppList(_ options: VerbOptions) {
    let host = options.require("host")
    let workDir = workDirectory(options)
    let pinnedCert = readServerCert(workDir)
    if pinnedCert == nil {
        FileHandle.standardError.write("applist needs a pinned server cert in \(serverCertPath(workDir)); run pair first\n".data(using: .utf8)!)
        exit(1)
    }
    let manager = MLCHttpManager(address: host, httpsPort: 0, serverCert: pinnedCert)!

    let response = MLCAppListResponse()
    guard let request = makeRequest(response, manager.newAppListRequest()) else {
        print("FAIL applist: no applist URL")
        exit(1)
    }
    manager.executeRequestSynchronously(request)

    print("transport=https-pinned status=\(response.statusCode) message=\(response.statusMessage ?? "")")
    guard response.isStatusOk() else { exit(1) }
    let apps = (response.getAppList() as? Set<AnyHashable> ?? []).compactMap { $0 as? MLCAppRecord }
    for app in apps.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
        print("app id=\(app.id ?? "") name=\(app.name ?? "") hdr=\(app.hdrSupported)")
    }
    print("app-count=\(apps.count)")
}

func runPair(_ options: VerbOptions) {
    let host = options.require("host")
    let pin = options.require("pin")
    let workDir = workDirectory(options)
    let (user, password) = webUICredentials(options)

    MLCCryptoManager.generateKeyPairUsingSSL()
    guard let clientCert = MLCCryptoManager.readCertFromFile() else {
        print("FAIL pair: no client certificate")
        exit(1)
    }

    let manager = MLCHttpManager(address: host, httpsPort: 0, serverCert: nil)!
    let callback = PairCallback()
    let pairManager = MLCPairManager(manager: manager, clientCert: clientCert, callback: callback, pin: pin)!

    let queue = OperationQueue()
    queue.addOperation(pairManager)

    guard callback.started.wait(timeout: .now() + 10) == .success else {
        print("FAIL pair: pair stack never started")
        exit(1)
    }
    guard let startedPin = callback.pin else {
        print("FAIL pair: no PIN from pair stack")
        exit(1)
    }
    print("PAIRING-STARTED pin=\(startedPin)")

    let webUI = WebUIClient(address: hostAddress(host), port: defaultWebUIPort, user: user, password: password)
    var pairingId: String?
    for _ in 0..<60 {
        if let pairings = webUI.pendingPairings() {
            if let pairing = pairings.first(where: { ($0["name"] as? String) == deviceName }) {
                pairingId = pairing["id"] as? String
                print("WEBUI-PAIRING id=\(pairingId ?? "") name=\(pairing["name"] as? String ?? "") address=\(pairing["address"] as? String ?? "")")
                break
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    guard let pairingId else {
        print("FAIL pair: no pending pairing for \(deviceName) appeared in the Sunshine web UI")
        exit(1)
    }

    let (accepted, detail) = webUI.submitPin(pairingId: pairingId, pin: startedPin)
    print("WEBUI-PIN-SUBMITTED pairing_id=\(pairingId) accepted=\(accepted) \(detail)")
    if !accepted {
        print("FAIL pair: Sunshine rejected the PIN submission")
        exit(1)
    }

    guard callback.finished.wait(timeout: .now() + 240) == .success else {
        print("FAIL pair: pairing did not finish in time")
        exit(1)
    }
    if callback.hasAlreadyPaired {
        print("PAIR-ALREADY-PAIRED")
        exit(0)
    }
    switch callback.result {
    case .success(let serverCert):
        let path = serverCertPath(workDir)
        try? serverCert.write(to: URL(fileURLWithPath: path), options: .atomic)
        print("PAIR-OK cert-sha256=\(sha256(serverCert)) stored=\(path)")
        exit(0)
    case .failure(let message):
        print("PAIR-FAILED phase=\(message)")
        exit(1)
    case nil:
        print("FAIL pair: pair stack finished without a result")
        exit(1)
    }
}

func runQuitApp(_ options: VerbOptions) {
    let host = options.require("host")
    let appID = options.require("app")
    let workDir = workDirectory(options)
    let pinnedCert = readServerCert(workDir)
    if pinnedCert == nil {
        FileHandle.standardError.write("quitapp needs a pinned server cert in \(serverCertPath(workDir)); run pair first\n".data(using: .utf8)!)
        exit(1)
    }
    let manager = MLCHttpManager(address: host, httpsPort: 0, serverCert: pinnedCert)!

    let response = MLCHttpResponse()
    guard let request = makeRequest(response, manager.newQuitAppRequest()) else {
        print("FAIL quitapp: no quit URL")
        exit(1)
    }
    manager.executeRequestSynchronously(request)
    print("quitapp app=\(appID) status=\(response.statusCode) message=\(response.statusMessage ?? "")")
    exit(response.statusCode == 200 ? 0 : 1)
}

let options = parseArguments()
_ = workDirectory(options)
MLCCryptoManager.setStorageDirectory(options.value("work-dir") ?? defaultWorkDir)

switch options.verb {
case "serverinfo": runServerInfo(options)
case "applist": runAppList(options)
case "pair": runPair(options)
case "quitapp": runQuitApp(options)
default:
    FileHandle.standardError.write("unknown verb \(options.verb)\n".data(using: .utf8)!)
    exit(2)
}
