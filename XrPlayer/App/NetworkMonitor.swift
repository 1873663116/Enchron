import Foundation
import Network

/// Observes network connectivity via NWPathMonitor.
public final class NetworkMonitor {
    public private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.enchron.networkmonitor")

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
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
}
