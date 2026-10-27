import Foundation
import Network

public struct MoonlightDiscoveredHost: Sendable, Equatable {
    public var instanceName: String
    public var host: String
    public var port: UInt16
    public var mac: String?

    public init(instanceName: String, host: String, port: UInt16, mac: String? = nil) {
        self.instanceName = instanceName
        self.host = host
        self.port = port
        self.mac = mac
    }
}

private final class ResolutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

public final class MoonlightDiscovery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.enchron.moonlight.discovery")
    private let lock = NSLock()
    private var browser: NWBrowser?
    private var resolved: [String: MoonlightDiscoveredHost] = [:]
    private var pendingResolutions: Set<String> = []
    private var discoveredMACs: [String: String] = [:]
    private var continuation: AsyncStream<[MoonlightDiscoveredHost]>.Continuation?

    public init() {}

    public func start() -> AsyncStream<[MoonlightDiscoveredHost]> {
        stop()

        let stream = AsyncStream<[MoonlightDiscoveredHost]> { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }

            let parameters = NWParameters()
            parameters.includePeerToPeer = false
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: "_nvstream._tcp", domain: nil),
                using: parameters
            )
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.handle(results: results)
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                }
            }
            lock.withLock { self.browser = browser }
            browser.start(queue: queue)
        }
        return stream
    }

    public func stop() {
        lock.lock()
        let browser = self.browser
        self.browser = nil
        let continuation = self.continuation
        self.continuation = nil
        resolved.removeAll()
        pendingResolutions.removeAll()
        discoveredMACs.removeAll()
        lock.unlock()
        browser?.cancel()
        continuation?.finish()
    }

    /// Sunshine and GFE advertise the wake-on-LAN target in the Bonjour text
    /// record, whose entries are typed rather than a plain dictionary.
    static func textRecordValue(_ key: String, in metadata: NWBrowser.Result.Metadata) -> String? {
        guard case .bonjour(let record) = metadata else { return nil }
        switch record.getEntry(for: key) {
        case .string(let value):
            return value
        case .data(let data):
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    private func handle(results: Set<NWBrowser.Result>) {
        var names: [String] = []
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            names.append(name)
            if let mac = Self.textRecordValue("mac", in: result.metadata) {
                lock.withLock { discoveredMACs[name] = mac }
            }
            lock.lock()
            let alreadyKnown = resolved[name] != nil || pendingResolutions.contains(name)
            if !alreadyKnown {
                pendingResolutions.insert(name)
            }
            lock.unlock()
            if !alreadyKnown {
                resolve(endpoint: result.endpoint, name: name)
            }
        }
        publish()
    }

    private func resolve(endpoint: NWEndpoint, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let gate = ResolutionGate()

        let complete: @Sendable (String?, UInt16?) -> Void = { [weak self] host, port in
            guard gate.begin() else { return }
            connection.cancel()
            guard let self else { return }
            self.lock.lock()
            self.pendingResolutions.remove(name)
            let mac = self.discoveredMACs[name]
            if let host, let port {
                self.resolved[name] = MoonlightDiscoveredHost(
                    instanceName: name,
                    host: host,
                    port: port,
                    mac: mac
                )
            }
            self.lock.unlock()
            self.publish()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let remote = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    complete(Self.hostString(from: host), port.rawValue)
                } else {
                    complete(nil, nil)
                }
            case .failed, .cancelled:
                complete(nil, nil)
            default:
                break
            }
        }
        connection.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 3) {
            complete(nil, nil)
        }
    }

    private func publish() {
        lock.lock()
        let snapshot = resolved.values.sorted { $0.instanceName < $1.instanceName }
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(snapshot)
    }

    /// Network.framework qualifies a resolved address with the interface it was
    /// reached on, as in `192.168.5.28%en1`, and the resolved port. The scope is
    /// not part of an address that later stages may carry: URL construction reads
    /// `%` as an escape and `getaddrinfo` rejects a scoped IPv4 literal.
    static func hostString(from host: NWEndpoint.Host) -> String {
        let description = "\(host)"
        guard let scope = description.firstIndex(of: "%") else { return description }
        return String(description[description.startIndex..<scope])
    }
}
