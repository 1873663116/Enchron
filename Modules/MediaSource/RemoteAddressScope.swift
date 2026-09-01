import Foundation
import Network

public enum RemoteAddressScope: Sendable, Equatable {
    case loopback
    case privateNetwork
    case linkLocal
    case carrierGradeNAT
    case multicastDNSName
    case unqualifiedName
    case publicAddress
    case qualifiedName

    public init(host: String) {
        let literal = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let address = IPv4Address(literal) {
            self = Self.scope(ofIPv4: address)
        } else if let address = IPv6Address(literal) {
            self = address.asIPv4.map(Self.scope(ofIPv4:)) ?? Self.scope(ofIPv6: address)
        } else if literal.lowercased().hasSuffix(".local") {
            self = .multicastDNSName
        } else if literal.contains(".") {
            self = .qualifiedName
        } else {
            self = .unqualifiedName
        }
    }

    public var keepsCleartextOffThePublicInternet: Bool {
        switch self {
        case .loopback, .privateNetwork, .linkLocal, .carrierGradeNAT,
             .multicastDNSName, .unqualifiedName:
            true
        case .publicAddress, .qualifiedName:
            false
        }
    }

    private static func scope(ofIPv4 address: IPv4Address) -> Self {
        let octets = [UInt8](address.rawValue)
        switch (octets[0], octets[1]) {
        case (127, _):
            return .loopback
        case (10, _), (192, 168):
            return .privateNetwork
        case (172, 16...31):
            return .privateNetwork
        case (169, 254):
            return .linkLocal
        case (100, 64...127):
            return .carrierGradeNAT
        default:
            return .publicAddress
        }
    }

    private static func scope(ofIPv6 address: IPv6Address) -> Self {
        let bytes = [UInt8](address.rawValue)
        if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] == 1 { return .loopback }
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return .linkLocal }
        if bytes[0] & 0xFE == 0xFC { return .privateNetwork }
        return .publicAddress
    }
}

public enum CleartextExposureDecision: Sendable, Equatable {
    case proceed
    case askBeforeSending(host: String)
}

public final class CleartextExposurePolicy: @unchecked Sendable {
    public typealias ApprovalHandler = @MainActor @Sendable (String) async -> Bool

    public static let shared = CleartextExposurePolicy()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var storedApprovalHandler: ApprovalHandler?

    public var approvalHandler: ApprovalHandler? {
        get { lock.withLock { storedApprovalHandler } }
        set { lock.withLock { storedApprovalHandler = newValue } }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func decision(for url: URL) -> CleartextExposureDecision {
        guard url.scheme?.lowercased() == "http",
              let host = url.host, host.isEmpty == false,
              RemoteAddressScope(host: host).keepsCleartextOffThePublicInternet == false,
              defaults.bool(forKey: Self.acknowledgementKey(host: host)) == false
        else { return .proceed }
        return .askBeforeSending(host: host)
    }

    public func authorize(_ url: URL) async -> Bool {
        guard case .askBeforeSending(let host) = decision(for: url) else { return true }
        guard let approvalHandler else { return true }
        guard await approvalHandler(host) else { return false }
        acknowledge(host: host)
        return true
    }

    public func acknowledge(host: String) {
        defaults.set(true, forKey: Self.acknowledgementKey(host: host))
    }

    private static func acknowledgementKey(host: String) -> String {
        "cleartext-exposure-acknowledged.\(host.lowercased())"
    }
}
