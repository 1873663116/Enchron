import Foundation

public struct StoredHost: Codable, Equatable {
    public var id: String
    public var name: String
    public var address: HostAddress
    public var serverCert: Data?
    public var preferredAppID: AppID?
    public var hasPairingRecord: Bool
}

public final class HostStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = base
                .appendingPathComponent("Enchron", isDirectory: true)
                .appendingPathComponent("streaming-hosts.json")
        }
    }

    public func load() -> [StoredHost] {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL) else {
                return []
            }
            return (try? JSONDecoder().decode([StoredHost].self, from: data)) ?? []
        }
    }

    public func save(_ hosts: [StoredHost]) {
        lock.withLock {
            do {
                let directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(hosts)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                NSLog("[Moonlight] host store write failed: %@", String(describing: error))
            }
        }
    }

    public func upsert(_ host: StoredHost) -> [StoredHost] {
        var hosts = load()
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        save(hosts)
        return hosts
    }

    public func remove(id: String) -> [StoredHost] {
        let hosts = load().filter { $0.id != id }
        save(hosts)
        return hosts
    }

    public func update(id: String, mutate: (inout StoredHost) -> Void) -> [StoredHost] {
        var hosts = load()
        if let index = hosts.firstIndex(where: { $0.id == id }) {
            mutate(&hosts[index])
        }
        save(hosts)
        return hosts
    }
}

extension StoredHost {
    public var hostID: HostID { HostID(rawValue: id) }
}
