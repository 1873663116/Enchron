import Foundation

struct SpatialPlatformExecutionLease: Equatable, Sendable {
    let executionID: UUID
    let requestID: UUID
    let capabilityID: UUID
    let capabilityGeneration: UInt64
    let mediaSessionID: String?
}

struct SpatialPlatformExecutionClaim<Capability> {
    let lease: SpatialPlatformExecutionLease
    let capability: Capability
}

struct SpatialPlatformExecutionLeaseRegistry<Capability> {
    private struct CapabilityEntry {
        let generation: UInt64
        let capability: Capability
    }

    private var capabilities: [UUID: CapabilityEntry] = [:]
    private var preferredCapabilityID: UUID?
    private var nextCapabilityGeneration: UInt64 = 1
    private(set) var activeLease: SpatialPlatformExecutionLease?

    var currentCapability: Capability? {
        currentEntry()?.entry.capability
    }

    @discardableResult
    mutating func register(
        _ capability: Capability,
        id: UUID
    ) -> SpatialPlatformExecutionLease? {
        let invalidatedLease =
            activeLease?.capabilityID == id ? invalidateActiveExecution() : nil
        capabilities[id] = CapabilityEntry(
            generation: nextCapabilityGeneration,
            capability: capability
        )
        nextCapabilityGeneration &+= 1
        if preferredCapabilityID == nil {
            preferredCapabilityID = id
        }
        return invalidatedLease
    }

    @discardableResult
    mutating func unregister(id: UUID) -> SpatialPlatformExecutionLease? {
        capabilities[id] = nil
        if preferredCapabilityID == id {
            preferredCapabilityID = capabilities.keys.first
        }
        guard activeLease?.capabilityID == id else { return nil }
        return invalidateActiveExecution()
    }

    mutating func claim(
        requestID: UUID,
        mediaSessionID: String?
    ) -> SpatialPlatformExecutionClaim<Capability>? {
        guard activeLease == nil,
              let current = currentEntry() else { return nil }
        let lease = SpatialPlatformExecutionLease(
            executionID: UUID(),
            requestID: requestID,
            capabilityID: current.id,
            capabilityGeneration: current.entry.generation,
            mediaSessionID: mediaSessionID
        )
        activeLease = lease
        return SpatialPlatformExecutionClaim(
            lease: lease,
            capability: current.entry.capability
        )
    }

    func isLive(_ lease: SpatialPlatformExecutionLease) -> Bool {
        guard activeLease == lease,
              capabilities[lease.capabilityID]?.generation
                == lease.capabilityGeneration else {
            return false
        }
        return true
    }

    @discardableResult
    mutating func invalidateActiveExecution() -> SpatialPlatformExecutionLease? {
        defer { activeLease = nil }
        return activeLease
    }

    mutating func finish(_ lease: SpatialPlatformExecutionLease) {
        guard activeLease == lease else { return }
        activeLease = nil
    }

    private func currentEntry() -> (id: UUID, entry: CapabilityEntry)? {
        if let preferredCapabilityID,
           let entry = capabilities[preferredCapabilityID] {
            return (preferredCapabilityID, entry)
        }
        guard let first = capabilities.first else { return nil }
        return (first.key, first.value)
    }
}

enum SpatialPlatformImmersiveRequestProvenance: Equatable, Sendable {
    case preexisting
    case openedByRequest
}

struct SpatialPlatformImmersiveRequestProvenanceRegistry {
    private var provenanceByRequestID:
        [UUID: SpatialPlatformImmersiveRequestProvenance] = [:]

    mutating func provenance(
        for requestID: UUID,
        observingOpenSpace: Bool
    ) -> SpatialPlatformImmersiveRequestProvenance? {
        if let provenance = provenanceByRequestID[requestID] {
            return provenance
        }
        guard observingOpenSpace else { return nil }
        provenanceByRequestID[requestID] = .preexisting
        return .preexisting
    }

    mutating func recordOpenedSpace(for requestID: UUID) {
        guard provenanceByRequestID[requestID] == nil else { return }
        provenanceByRequestID[requestID] = .openedByRequest
    }

    mutating func clear(requestID: UUID) {
        provenanceByRequestID[requestID] = nil
    }

    mutating func retainOnly(requestID: UUID?) {
        guard let requestID,
              let provenance = provenanceByRequestID[requestID] else {
            provenanceByRequestID.removeAll()
            return
        }
        provenanceByRequestID = [requestID: provenance]
    }
}

@MainActor
final class SpatialPlatformSerializedActionLane {
    private var tail: Task<Void, Never>?

    func perform<Result: Sendable>(
        isLive: @escaping @MainActor () -> Bool,
        operation: @escaping @MainActor () async -> Result
    ) async -> Result? {
        guard isLive() else { return nil }
        let predecessor = tail
        let operationTask = Task { @MainActor () -> Result? in
            if let predecessor {
                await predecessor.value
                guard isLive() else { return nil }
            }
            guard isLive() else { return nil }
            let result = await operation()
            guard isLive() else { return nil }
            return result
        }
        tail = Task { @MainActor in
            _ = await operationTask.value
        }
        let result = await operationTask.value
        guard isLive() else { return nil }
        return result
    }
}
