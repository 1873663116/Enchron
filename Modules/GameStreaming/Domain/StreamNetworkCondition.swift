import Darwin
import Foundation

/// Decides whether a session is local or crosses the internet, which is what
/// chooses the video packet size.
///
/// Moonlight lets the library guess from the target address alone. That guess
/// misses a LAN address reached through a VPN tunnel, where the host is local by
/// address but the path is not, so the tunnel is checked as well.
public enum StreamNetworkCondition {
    public struct Plan: Sendable, Equatable {
        public var streamingRemotely: Bool
        public var packetSize: Int
        public var vpnDetected: Bool

        public var readableValue: String {
            "remote=\(streamingRemotely);vpn=\(vpnDetected);packetSize=\(packetSize)"
        }
    }

    public static let localPacketSize = 1392
    public static let remotePacketSize = 1024

    public static func plan(for address: HostAddress, vpnActive: Bool = vpnDetected()) -> Plan {
        let remoteByAddress = !isPrivateAddress(address.host)
        let streamingRemotely = remoteByAddress || vpnActive
        return Plan(
            streamingRemotely: streamingRemotely,
            packetSize: streamingRemotely ? remotePacketSize : localPacketSize,
            vpnDetected: vpnActive
        )
    }

    /// Private IPv4 (RFC 1918), loopback, link-local and IPv6 unique-local and
    /// link-local addresses are local. A host name is treated as local, because
    /// the name resolution has already produced the address that was dialed.
    public static func isPrivateAddress(_ host: String) -> Bool {
        if host.isEmpty || host == "localhost" || host.hasSuffix(".local") {
            return true
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            if parts[0] == 10 { return true }
            if parts[0] == 127 { return true }
            if parts[0] == 192, parts[1] == 168 { return true }
            if parts[0] == 172, (16...31).contains(parts[1]) { return true }
            if parts[0] == 169, parts[1] == 254 { return true }
            return false
        }
        if host.contains(":") {
            let lowered = host.lowercased()
            if lowered.hasPrefix("fe80") || lowered.hasPrefix("fc") || lowered.hasPrefix("fd") {
                return true
            }
            if lowered == "::1" { return true }
            return false
        }
        return true
    }

    /// A tunnel interface appears as `utun`, `ipsec`, `ppp` or `tap`. The check
    /// only decides packet size, so a false positive costs one extra small
    /// packet class, never a failed session.
    public static func vpnDetected() -> Bool {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return false }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: entry.pointee.ifa_name)
            if name.hasPrefix("utun")
                || name.hasPrefix("ipsec")
                || name.hasPrefix("ppp")
                || name.hasPrefix("tap") {
                return true
            }
        }
        return false
    }
}
