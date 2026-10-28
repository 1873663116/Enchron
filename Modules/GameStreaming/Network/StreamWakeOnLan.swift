import Darwin
import Foundation

/// Sends the magic packet a suspended host listens for.
///
/// The packet goes out on every port Moonlight tries: the standard port, the
/// one its internet hosting tool opens, and the dynamic range the streaming
/// server keeps open. Any of them can be the only one a router forwards, and the
/// packet is small enough that sending all of them costs nothing.
public enum StreamWakeOnLan {
    private static let ports: [UInt16] = [
        9, 47_009, 47_998, 47_999, 48_000, 48_002, 48_010
    ]

    static func send(to hosts: [String], mac: String) -> Int {
        guard let payload = magicPacket(mac: mac) else { return 0 }
        var delivered = 0
        for host in hosts {
            for port in ports {
                delivered += datagram(payload, host: host, port: port)
            }
        }
        return delivered
    }

    public static func magicPacket(mac: String) -> Data? {
        let hex = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: bytes)
        }
        return packet
    }

    private static func datagram(_ payload: Data, host: String, port: UInt16) -> Int {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return 0 }
        defer { close(descriptor) }

        var broadcast: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &broadcast,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return 0 }

        let sent = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                payload.withUnsafeBytes { buffer in
                    sendto(
                        descriptor,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
        return sent > 0 ? 1 : 0
    }
}
