import CryptoKit
import Foundation
import Security

public struct ServerCertificateInfo: Sendable, Equatable, Identifiable {
    public var id: String { address }
    public let address: String
    public let certificateName: String
    public let sha256Fingerprint: String
    public let validFrom: Date?
    public let validUntil: Date?

    public init(
        address: String,
        certificateName: String,
        sha256Fingerprint: String,
        validFrom: Date?,
        validUntil: Date?
    ) {
        self.address = address
        self.certificateName = certificateName
        self.sha256Fingerprint = sha256Fingerprint
        self.validFrom = validFrom
        self.validUntil = validUntil
    }
}

public final class ServerTrustPolicy: NSObject, URLSessionDelegate, @unchecked Sendable {
    public typealias ApprovalHandler = @MainActor @Sendable (ServerCertificateInfo) async -> Bool

    public static let shared = ServerTrustPolicy()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var connectionApprovalDepth: [String: Int] = [:]
    private var storedApprovalHandler: ApprovalHandler?

    public var approvalHandler: ApprovalHandler? {
        get { lock.withLock { storedApprovalHandler } }
        set { lock.withLock { storedApprovalHandler = newValue } }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func withConnectionApproval<T: Sendable>(
        to url: URL,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let address = Self.address(for: url)
        lock.withLock { connectionApprovalDepth[address, default: 0] += 1 }
        defer {
            lock.withLock {
                let remaining = (connectionApprovalDepth[address] ?? 1) - 1
                if remaining == 0 { connectionApprovalDepth.removeValue(forKey: address) }
                else { connectionApprovalDepth[address] = remaining }
            }
        }
        return try await operation()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let address = Self.address(
            host: challenge.protectionSpace.host,
            port: challenge.protectionSpace.port
        )
        let fingerprint = Self.fingerprint(of: certificate)
        if defaults.string(forKey: Self.fingerprintKey(address: address)) == fingerprint {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        let mayAsk = lock.withLock { (connectionApprovalDepth[address] ?? 0) > 0 }
        guard mayAsk, let approvalHandler else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let validity = Self.validity(of: certificate)
        let info = ServerCertificateInfo(
            address: address,
            certificateName: SecCertificateCopySubjectSummary(certificate) as String? ?? "Unknown",
            sha256Fingerprint: fingerprint,
            validFrom: validity.from,
            validUntil: validity.until
        )
        Task { @MainActor [defaults] in
            if await approvalHandler(info) {
                defaults.set(fingerprint, forKey: Self.fingerprintKey(address: address))
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }

    private static func fingerprint(of certificate: SecCertificate) -> String {
        SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }

    private struct DERElement {
        let tag: UInt8
        let content: Range<Int>
    }

    private static func validity(of certificate: SecCertificate) -> (from: Date?, until: Date?) {
        let data = SecCertificateCopyData(certificate) as Data
        guard let certificateSequence = element(in: data, at: 0),
              let tbsCertificate = children(of: certificateSequence, in: data).first else {
            return (nil, nil)
        }
        let fields = children(of: tbsCertificate, in: data)
        let validityIndex = fields.first?.tag == 0xA0 ? 4 : 3
        guard fields.indices.contains(validityIndex) else { return (nil, nil) }
        let dates = children(of: fields[validityIndex], in: data)
        guard dates.count == 2 else { return (nil, nil) }
        return (date(from: dates[0], in: data), date(from: dates[1], in: data))
    }

    private static func children(of parent: DERElement, in data: Data) -> [DERElement] {
        var offset = parent.content.lowerBound
        var result: [DERElement] = []
        while offset < parent.content.upperBound, let child = element(in: data, at: offset) {
            result.append(child)
            offset = child.content.upperBound
        }
        return result
    }

    private static func element(in data: Data, at offset: Int) -> DERElement? {
        guard offset + 2 <= data.count else { return nil }
        let tag = data[offset]
        let firstLength = Int(data[offset + 1])
        let headerLength: Int
        let contentLength: Int
        if firstLength & 0x80 == 0 {
            headerLength = 2
            contentLength = firstLength
        } else {
            let byteCount = firstLength & 0x7F
            guard byteCount > 0, byteCount <= 4, offset + 2 + byteCount <= data.count else { return nil }
            headerLength = 2 + byteCount
            contentLength = (0..<byteCount).reduce(0) { length, index in
                (length << 8) | Int(data[offset + 2 + index])
            }
        }
        let lower = offset + headerLength
        let upper = lower + contentLength
        guard upper <= data.count else { return nil }
        return DERElement(tag: tag, content: lower..<upper)
    }

    private static func date(from element: DERElement, in data: Data) -> Date? {
        guard let value = String(data: data[element.content], encoding: .ascii) else { return nil }
        let normalized: String
        switch element.tag {
        case 0x17:
            guard value.count >= 2, let year = Int(value.prefix(2)) else { return nil }
            normalized = "\(year >= 50 ? "19" : "20")\(value)"
        case 0x18:
            normalized = value
        default:
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmss'Z'"
        return formatter.date(from: normalized)
    }

    private static func address(for url: URL) -> String {
        address(host: url.host ?? "", port: url.port ?? defaultPort(for: url.scheme))
    }

    private static func address(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    private static func defaultPort(for scheme: String?) -> Int {
        scheme?.lowercased() == "http" ? 80 : 443
    }

    private static func fingerprintKey(address: String) -> String {
        "server-certificate-fingerprint.\(address)"
    }
}

public final class MediaSourceNetwork: @unchecked Sendable {
    public static let shared = MediaSourceNetwork()

    public let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        session = URLSession(
            configuration: configuration,
            delegate: ServerTrustPolicy.shared,
            delegateQueue: nil
        )
    }

    public func withConnectionApproval<T: Sendable>(
        to url: URL,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await ServerTrustPolicy.shared.withConnectionApproval(to: url, operation: operation)
    }
}
