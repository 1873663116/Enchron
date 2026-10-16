import Foundation
import Network

public struct MoonlightDiscoveredHost: Sendable, Equatable {
    public var instanceName: String
    public var host: String
    public var port: UInt16
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
                for: .bonjour(type: "_nvstream._tcp", domain: nil),
                using: parameters
            )
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.handle(results: results)
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    // The browser stays stopped; a later start() restarts it.
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
        lock.unlock()
        browser?.cancel()
        continuation?.finish()
    }

    private func handle(results: Set<NWBrowser.Result>) {
        var names: [String] = []
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            names.append(name)
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
            if let host, let port {
                self.resolved[name] = MoonlightDiscoveredHost(instanceName: name, host: host, port: port)
            }
            self.lock.unlock()
            self.publish()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let remote = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    complete("\(host)", port.rawValue)
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
}
