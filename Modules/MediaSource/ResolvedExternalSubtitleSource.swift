import Foundation

public struct ResolvedExternalSubtitleSource: @unchecked Sendable, Equatable, Identifiable {
    public let id: String
    public let url: URL
    public let displayName: String
    public let versionedIdentity: VersionedMediaIdentity?
    public let accessLease: MediaAccessLease?
    public let byteStreamHandle: MediaByteStreamHandle?

    public init(
        id: String,
        url: URL,
        displayName: String,
        versionedIdentity: VersionedMediaIdentity? = nil,
        accessLease: MediaAccessLease? = nil,
        byteStreamHandle: MediaByteStreamHandle? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.versionedIdentity = versionedIdentity
        self.accessLease = accessLease
        self.byteStreamHandle = byteStreamHandle
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.url == rhs.url
            && lhs.displayName == rhs.displayName
            && lhs.versionedIdentity == rhs.versionedIdentity
    }
}

@MainActor
public final class ExternalSubtitleDiscovery: Equatable {
    public enum DiscoveryError: Error, Sendable, Equatable {
        case deadlineExceeded
    }

    nonisolated public let id = UUID()
    private let operation: @MainActor @Sendable () async throws -> [ResolvedExternalSubtitleSource]

    public init(
        operation: @escaping @MainActor @Sendable () async throws -> [ResolvedExternalSubtitleSource]
    ) {
        self.operation = operation
    }

    public func resolve(
        discardingLateSources: (@MainActor @Sendable ([ResolvedExternalSubtitleSource]) -> Void)? = nil
    ) async throws -> [ResolvedExternalSubtitleSource] {
        try await resolve(deadline: .seconds(30), discardingLateSources: discardingLateSources)
    }

    func resolve(
        deadline: Duration,
        discardingLateSources: (@MainActor @Sendable ([ResolvedExternalSubtitleSource]) -> Void)? = nil
    ) async throws -> [ResolvedExternalSubtitleSource] {
        let resolution = Resolution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                resolution.continuation = continuation
                resolution.task = Task { [operation] in
                    do {
                        let sources = try await operation()
                        if !resolution.finish(.success(sources)) {
                            if let discardingLateSources {
                                discardingLateSources(sources)
                            } else {
                                for source in sources {
                                    source.accessLease?.release()
                                    source.byteStreamHandle?.release()
                                }
                            }
                        }
                    } catch {
                        resolution.finish(.failure(error))
                    }
                }
                resolution.deadline = Task {
                    do { try await Task.sleep(for: deadline) } catch { return }
                    resolution.task?.cancel()
                    resolution.finish(.failure(DiscoveryError.deadlineExceeded))
                }
            }
        } onCancel: {
            Task { @MainActor in
                resolution.task?.cancel()
                resolution.finish(.failure(CancellationError()))
            }
        }
    }

    nonisolated public static func == (lhs: ExternalSubtitleDiscovery, rhs: ExternalSubtitleDiscovery) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor
    private final class Resolution {
        var task: Task<Void, Never>?
        var deadline: Task<Void, Never>?
        var continuation: CheckedContinuation<[ResolvedExternalSubtitleSource], any Error>?

        @discardableResult
        func finish(_ result: Result<[ResolvedExternalSubtitleSource], any Error>) -> Bool {
            guard let continuation else { return false }
            self.continuation = nil
            deadline?.cancel()
            continuation.resume(with: result)
            return true
        }
    }
}
