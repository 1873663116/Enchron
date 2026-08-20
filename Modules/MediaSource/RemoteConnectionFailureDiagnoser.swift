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

public enum RemoteConnectionFailureDiagnosis: Sendable, Equatable {
    case requiresHTTPS
    case unclassified
}

public enum RemoteConnectionError: LocalizedError, Sendable {
    case requiresHTTPS

    public var errorDescription: String? {
        switch self {
        case .requiresHTTPS:
            "该地址需要使用 HTTPS。请在服务器地址前添加 https:// 后重试。"
        }
    }
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
    ) async -> RemoteConnectionFailureDiagnosis {
        if Self.containsURLFailure(
            error,
            code: NSURLErrorAppTransportSecurityRequiresSecureConnection
        ) {
            return .requiresHTTPS
        }

        guard attemptedURL.scheme?.lowercased() == "http",
              Self.containsURLFailure(error),
              let endpoint = RemoteConnectionEndpoint(httpURL: attemptedURL)
        else {
            return .unclassified
        }

        return await tlsProbe(endpoint) ? .requiresHTTPS : .unclassified
    }

    private static func containsURLFailure(
        _ error: any Error,
        code expectedCode: Int? = nil
    ) -> Bool {
        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []

        while let candidate = current {
            let identity = ObjectIdentifier(candidate)
            guard visited.insert(identity).inserted else { return false }
            if candidate.domain == NSURLErrorDomain,
               expectedCode == nil || candidate.code == expectedCode {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
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
