import Foundation

public struct HostID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AppID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct SessionID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }
}

public struct PairingID: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID().uuidString
    }
}

public struct HostAddress: Hashable, Sendable, Codable {
    public var host: String
    public var portBase: UInt16

    public static let defaultPortBase: UInt16 = 47989

    public init(host: String, portBase: UInt16 = HostAddress.defaultPortBase) {
        self.host = host
        self.portBase = portBase
    }

    public init?(parsing input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("["), let closing = trimmed.firstIndex(of: "]") {
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
            let remainder = trimmed[trimmed.index(after: closing)...]
            if remainder.hasPrefix(":") {
                guard let port = UInt16(remainder.dropFirst()), port > 0 else {
                    return nil
                }
                self.init(host: host, portBase: port)
            } else if remainder.isEmpty {
                self.init(host: host)
            } else {
                return nil
            }
            return
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            self.init(host: trimmed)
        case 2:
            guard let port = UInt16(parts[1]), port > 0 else {
                return nil
            }
            self.init(host: String(parts[0]), portBase: port)
        default:
            return nil
        }
    }

    public var displayString: String {
        portBase == HostAddress.defaultPortBase ? host : "\(host):\(portBase)"
    }

    public var httpPort: UInt16 { portBase }
    public var httpsPort: UInt16 { portBase &- 5 }
    public var rtspPort: UInt16 { portBase &+ 21 }
    public var portOffset: Int { Int(portBase) - Int(HostAddress.defaultPortBase) }
}

public enum HostReachability: String, Sendable, Codable {
    case unknown
    case online
    case offline

    public var readableValue: String { rawValue }
}

public enum PairingState: Sendable, Equatable {
    case unknown
    case unpaired
    case paired
    case failed(String)

    public var readableValue: String {
        switch self {
        case .unknown: "unknown"
        case .unpaired: "unpaired"
        case .paired: "paired"
        case .failed: "failed"
        }
    }

    public var isPaired: Bool {
        if case .paired = self { return true }
        return false
    }
}

public enum HostApplicationsState: Sendable, Equatable {
    case unknown
    case loaded([HostApplication])
    case failed(String)

    public var applications: [HostApplication]? {
        if case .loaded(let apps) = self { return apps }
        return nil
    }
}

public struct RemoteSessionInfo: Sendable, Equatable {
    public var currentGame: String?
    public var rawState: String?

    public init(currentGame: String? = nil, rawState: String? = nil) {
        self.currentGame = currentGame
        self.rawState = rawState
    }

    public var isBusy: Bool {
        rawState?.hasSuffix("_SERVER_BUSY") == true
    }
}

public struct HostApplication: Sendable, Equatable, Identifiable {
    public let id: AppID
    public var name: String
    public var hdrSupported: Bool

    public init(id: AppID, name: String, hdrSupported: Bool = false) {
        self.id = id
        self.name = name
        self.hdrSupported = hdrSupported
    }
}

public struct HostSnapshot: Sendable, Equatable, Identifiable {
    public let id: HostID
    public var name: String
    public var address: HostAddress
    public var reachability: HostReachability
    public var pairing: PairingState
    public var applications: HostApplicationsState
    public var remoteSession: RemoteSessionInfo?

    public init(
        id: HostID,
        name: String,
        address: HostAddress,
        reachability: HostReachability = .unknown,
        pairing: PairingState = .unknown,
        applications: HostApplicationsState = .unknown,
        remoteSession: RemoteSessionInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.reachability = reachability
        self.pairing = pairing
        self.applications = applications
        self.remoteSession = remoteSession
    }

    public var statusLight: HostStatusLight {
        if case .paired = pairing {
            return reachability == .online ? .green : .red
        }
        if case .failed = pairing {
            return .red
        }
        return reachability == .offline ? .red : .yellow
    }

    public var readableStatus: String {
        "pairing=\(pairing.readableValue);reachability=\(reachability.readableValue)"
    }
}

public enum HostStatusLight: String, Sendable {
    case green
    case yellow
    case red
}

public struct PairingChallenge: Sendable, Equatable, Identifiable {
    public let id: PairingID
    public let pin: String
    public var state: PairingState

    public init(id: PairingID, pin: String, state: PairingState = .unpaired) {
        self.id = id
        self.pin = pin
        self.state = state
    }
}
