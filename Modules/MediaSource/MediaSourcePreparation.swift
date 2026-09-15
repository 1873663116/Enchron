import Foundation

@MainActor
public final class MediaSourcePreparation {
    private var currentID: UUID?
    private var cancelTask: (() -> Void)?
    private var isSuspended = false

    public init() {}

    public func suspend() {
        isSuspended = true
        cancel()
    }

    public func resume() {
        isSuspended = false
    }

    public func cancel() {
        currentID = nil
        cancelTask?()
        cancelTask = nil
    }

    public func resolve<Value: Sendable>(
        _ operation: @escaping @MainActor () async throws -> Value
    ) async throws -> Value {
        guard !isSuspended else { throw CancellationError() }
        cancel()
        let id = UUID()
        currentID = id
        let resources = MediaSourcePreparationResources()
        let task = Task { @MainActor in
            try await MediaSourcePreparationResources.$current.withValue(resources) {
                try Task.checkCancellation()
                let value = try await operation()
                try Task.checkCancellation()
                return value
            }
        }
        cancelTask = {
            resources.cancel()
            task.cancel()
        }
        defer {
            if currentID == id {
                currentID = nil
                cancelTask = nil
            }
        }
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                resources.cancel()
                task.cancel()
            }
            guard currentID == id, !task.isCancelled, !Task.isCancelled else {
                throw CancellationError()
            }
            resources.handOff()
            return value
        } catch {
            resources.cancel()
            guard currentID == id, !task.isCancelled else { throw CancellationError() }
            throw error
        }
    }
}
