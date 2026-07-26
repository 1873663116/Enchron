import Foundation
import Network

public nonisolated protocol NetworkConnectivityWaiting: Sendable {
    func waitForConnection(timeout: Duration) async -> Bool
}

/// Observes network connectivity via NWPathMonitor.
nonisolated final class NetworkMonitor: NetworkConnectivityWaiting, @unchecked Sendable {
    public var isConnected: Bool {
        stateLock.withLock { _isConnected }
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.enchron.networkmonitor")
    private let stateLock = NSLock()
    private var _isConnected: Bool = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.setIsConnected(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Suspends until the network becomes available, or returns immediately if already connected.
    func waitForConnection(timeout: Duration) async -> Bool {
        if isConnected { return true }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return false }
            if isConnected { return true }
        }
        return false
    }

    private func setIsConnected(_ value: Bool) {
        stateLock.withLock {
            _isConnected = value
        }
    }
}

public nonisolated enum MediaSourceServices {
    public static func makeNetworkConnectivityWaiter() -> any NetworkConnectivityWaiting {
        NetworkMonitor()
    }
}
