import Foundation
import Network

/// Observes network connectivity via NWPathMonitor.
public nonisolated final class NetworkMonitor: @unchecked Sendable {
    public var isConnected: Bool {
        stateLock.withLock { _isConnected }
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.enchron.networkmonitor")
    private let stateLock = NSLock()
    private var _isConnected: Bool = true

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.setIsConnected(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Suspends until the network becomes available, or returns immediately if already connected.
    public func waitForConnection(timeout: Duration = .seconds(30)) async -> Bool {
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
