import Foundation

/// Keeps the last application list seen for each host.
///
/// The list changes rarely and the host is often asleep when the app starts, so
/// the stored copy is what fills the grid before the first successful refresh
/// and what keeps it filled when the refresh fails.
public final class ApplicationCacheStore: @unchecked Sendable {
    public struct Entry: Codable, Sendable {
        public var hostID: String
        public var fetchedAt: Date
        public var applications: [Application]

        public init(hostID: String, fetchedAt: Date, applications: [Application]) {
            self.hostID = hostID
            self.fetchedAt = fetchedAt
            self.applications = applications
        }
    }

    public struct Application: Codable, Sendable {
        public var id: String
        public var name: String
        public var hdrSupported: Bool

        public init(id: String, name: String, hdrSupported: Bool) {
            self.id = id
            self.name = name
            self.hdrSupported = hdrSupported
        }
    }

    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("enchron-app-lists", isDirectory: true)
        }
    }

    public func load(hostID: String) -> [Application]? {
        lock.withLock {
            guard let data = try? Data(contentsOf: fileURL(hostID: hostID)),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data)
            else {
                return nil
            }
            return entry.applications
        }
    }

    public func save(hostID: String, applications: [Application], now: Date = Date()) {
        lock.withLock {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let entry = Entry(hostID: hostID, fetchedAt: now, applications: applications)
                let data = try JSONEncoder().encode(entry)
                try data.write(to: fileURL(hostID: hostID), options: .atomic)
            } catch {
                NSLog("[Moonlight] application cache write failed: %@", String(describing: error))
            }
        }
    }

    public func remove(hostID: String) {
        lock.withLock {
            try? FileManager.default.removeItem(at: fileURL(hostID: hostID))
        }
    }

    private func fileURL(hostID: String) -> URL {
        let safe = hostID.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("host-\(safe).json")
    }
}

/// Caps how many artwork downloads run at once, so a grid of thirty applications
/// does not open thirty parallel requests against one host.
public actor ArtworkFetchLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int = 4) {
        self.limit = limit
    }

    public func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        active += 1
    }

    public func release() {
        active = max(active - 1, 0)
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        }
    }
}
