import Foundation
import Network
import Security

public struct RemoteConnectionEndpoint: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public enum RemoteConnectionFailure: LocalizedError, Sendable, Equatable, CaseIterable {
    case credentialsRejected
    case serverUnreachable
    case invalidAddress
    case requiresHTTPS

    public var errorDescription: String? {
        switch self {
        case .credentialsRejected:
            "Credentials rejected. Check your username and password."
        case .serverUnreachable:
            "Server unreachable. Check the address and your network connection."
        case .invalidAddress:
            "Invalid address. Check the server address and try again."
        case .requiresHTTPS:
            "This server requires HTTPS. Add https:// to the address and try again."
        }
    }
}

public enum RemoteConnectionResult: Sendable, Equatable {
    case connected
    case failed(RemoteConnectionFailure)
}

public struct RemoteConnectionFailureDiagnoser: Sendable {
    public typealias TLSProbe = @Sendable (RemoteConnectionEndpoint) async -> Bool

    public static let live = Self { endpoint in
        await RemoteTLSHandshakeProbe.canEstablishTLS(to: endpoint)
    }

    private let tlsProbe: TLSProbe

    public init(tlsProbe: @escaping TLSProbe) {
        self.tlsProbe = tlsProbe
    }

    public func diagnose(
        _ error: any Error,
        attemptedURL: URL
    ) async -> RemoteConnectionFailure {
        guard let urlFailureCode = Self.urlFailureCode(in: error) else {
            return .serverUnreachable
        }

        switch URLError.Code(rawValue: urlFailureCode) {
        case .userAuthenticationRequired, .userCancelledAuthentication:
            return .credentialsRejected
        case .badURL, .unsupportedURL:
            return .invalidAddress
        default:
            break
        }

        if attemptedURL.scheme?.lowercased() == "http",
           let endpoint = RemoteConnectionEndpoint(httpURL: attemptedURL),
           await tlsProbe(endpoint) {
            return .requiresHTTPS
        }

        return .serverUnreachable
    }

    private static func urlFailureCode(in error: any Error) -> Int? {
        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []

        while let candidate = current {
            let identity = ObjectIdentifier(candidate)
            guard visited.insert(identity).inserted else { return nil }
            if candidate.domain == NSURLErrorDomain {
                return candidate.code
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }
}

private extension RemoteConnectionEndpoint {
    init?(httpURL: URL) {
        guard let host = httpURL.host, host.isEmpty == false else { return nil }
        let portValue = httpURL.port ?? 80
        guard let port = UInt16(exactly: portValue), port > 0 else { return nil }
        self.init(host: host, port: port)
    }
}

private enum RemoteTLSHandshakeProbe {
    private static let queue = DispatchQueue(
        label: "app.enchron.remote-tls-handshake-probe",
        qos: .userInitiated
    )
    private static let timeout: DispatchTimeInterval = .seconds(3)

    static func canEstablishTLS(to endpoint: RemoteConnectionEndpoint) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { return false }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            queue
        )
        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: port,
            using: NWParameters(tls: tlsOptions)
        )
        let result = TLSHandshakeResult()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                result.install(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        result.resolve(true)
                        connection.cancel()
                    case .failed, .cancelled:
                        result.resolve(false)
                    case .setup, .preparing, .waiting:
                        break
                    @unknown default:
                        result.resolve(false)
                        connection.cancel()
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) {
                    result.resolve(false)
                    connection.cancel()
                }
            }
        } onCancel: {
            result.resolve(false)
            connection.cancel()
        }
    }
}

private nonisolated final class TLSHandshakeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var resolvedValue: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
        let resolvedValue = lock.withLock { () -> Bool? in
            if let resolvedValue {
                return resolvedValue
            }
            self.continuation = continuation
            return nil
        }
        if let resolvedValue {
            continuation.resume(returning: resolvedValue)
        }
    }

    func resolve(_ value: Bool) {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            guard resolvedValue == nil else { return nil }
            resolvedValue = value
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: value)
    }
}
