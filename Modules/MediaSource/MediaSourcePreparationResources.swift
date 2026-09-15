import Foundation

nonisolated public final class MediaSourcePreparationResources: @unchecked Sendable {
    @TaskLocal public static var current: MediaSourcePreparationResources?
    private let lock = NSLock()
    private var handles: [MediaByteStreamHandle] = []
    private var servers: [MediaByteStreamServer] = []
    private var isCancelled = false

    public init() {}

    func hold(_ server: MediaByteStreamServer) throws {
        let accepted = lock.withLock {
            guard !isCancelled else { return false }
            if !servers.contains(where: { $0 === server }) { servers.append(server) }
            return true
        }
        if !accepted {
            server.stop()
            throw CancellationError()
        }
    }

    func hold(_ handle: MediaByteStreamHandle) throws {
        let accepted = lock.withLock {
            guard !isCancelled else { return false }
            handles.append(handle)
            return true
        }
        if !accepted {
            handle.release()
            throw CancellationError()
        }
    }

    public func cancel() {
        let retiring = lock.withLock {
            isCancelled = true
            let retiring = (handles, servers)
            handles = []
            servers = []
            return retiring
        }
        retiring.0.forEach { $0.release() }
        retiring.1.forEach { $0.stop() }
    }

    public func handOff() {
        lock.withLock {
            handles = []
            servers = []
        }
    }
}
