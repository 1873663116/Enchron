import Foundation
import PlaybackPresentation

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
    private var retiredCapabilityIDs: Set<UUID> = []
    private var preferredCapabilityID: UUID?
    private var nextCapabilityGeneration: UInt64 = 1
    private(set) var activeLease: SpatialPlatformExecutionLease?

    var registeredCapabilityCount: Int {
        capabilities.keys.reduce(into: 0) { count, id in
            if retiredCapabilityIDs.contains(id) == false {
                count += 1
            }
        }
    }

    var currentCapability: Capability? {
        currentEntry()?.entry.capability
    }

    @discardableResult
    mutating func preferCapability(id: UUID) -> Bool {
        guard capabilities[id] != nil,
              retiredCapabilityIDs.contains(id) == false else {
            return false
        }
        preferredCapabilityID = id
        return true
    }

    @discardableResult
    mutating func register(
        _ capability: Capability,
        id: UUID,
        makePreferred: Bool = false
    ) -> SpatialPlatformExecutionLease? {
        let invalidatedLease =
            activeLease?.capabilityID == id ? invalidateActiveExecution() : nil
        retiredCapabilityIDs.remove(id)
        capabilities[id] = CapabilityEntry(
            generation: nextCapabilityGeneration,
            capability: capability
        )
        nextCapabilityGeneration &+= 1
        if preferredCapabilityID == nil || makePreferred {
            preferredCapabilityID = id
        }
        return invalidatedLease
    }

    @discardableResult
    mutating func unregister(
        id: UUID,
        preferredFallbackID: UUID? = nil
    ) -> SpatialPlatformExecutionLease? {
        guard capabilities[id] != nil else { return nil }
        if activeLease?.capabilityID == id {
            retiredCapabilityIDs.insert(id)
            if preferredCapabilityID == id {
                preferredCapabilityID = liveCapabilityID(
                    preferredFallbackID
                ) ?? firstRegisteredCapabilityID()
            }
            return nil
        }
        capabilities[id] = nil
        retiredCapabilityIDs.remove(id)
        if preferredCapabilityID == id {
            preferredCapabilityID = liveCapabilityID(preferredFallbackID)
                ?? firstRegisteredCapabilityID()
        }
        return nil
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
        guard let activeLease else { return nil }
        self.activeLease = nil
        removeRetiredCapabilityAfterExecutionEnds(activeLease.capabilityID)
        return activeLease
    }

    mutating func finish(_ lease: SpatialPlatformExecutionLease) {
        guard activeLease == lease else { return }
        activeLease = nil
        removeRetiredCapabilityAfterExecutionEnds(lease.capabilityID)
    }

    private func currentEntry() -> (id: UUID, entry: CapabilityEntry)? {
        if let preferredCapabilityID,
           retiredCapabilityIDs.contains(preferredCapabilityID) == false,
           let entry = capabilities[preferredCapabilityID] {
            return (preferredCapabilityID, entry)
        }
        guard let firstID = firstRegisteredCapabilityID(),
              let entry = capabilities[firstID] else { return nil }
        return (firstID, entry)
    }

    private func firstRegisteredCapabilityID() -> UUID? {
        capabilities.keys.first { retiredCapabilityIDs.contains($0) == false }
    }

    private func liveCapabilityID(_ id: UUID?) -> UUID? {
        guard let id,
              capabilities[id] != nil,
              retiredCapabilityIDs.contains(id) == false else {
            return nil
        }
        return id
    }

    /// A scene that disappears cannot accept another platform request. Its
    /// active lease remains valid so the same execution can continue through a
    /// newly registered scene root, while `currentCapability` stops exposing the
    /// retired scene's actions immediately.
    private mutating func removeRetiredCapabilityAfterExecutionEnds(
        _ capabilityID: UUID
    ) {
        guard retiredCapabilityIDs.remove(capabilityID) != nil else { return }
        capabilities[capabilityID] = nil
        if preferredCapabilityID == capabilityID {
            preferredCapabilityID = firstRegisteredCapabilityID()
        }
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

struct SpatialPlatformImmersiveSpaceObservation {
    private(set) var residency: SpatialPlatformImmersiveSpaceResidency?
    private(set) var revision: UInt64 = 0

    mutating func record(_ residency: SpatialPlatformImmersiveSpaceResidency) {
        self.residency = residency
        revision &+= 1
    }

    func confirms(
        _ residency: SpatialPlatformImmersiveSpaceResidency,
        after revision: UInt64
    ) -> Bool {
        self.revision > revision && self.residency == residency
    }
}

enum SpatialPlatformWindowIdentity: String, Hashable, Sendable {
    case main
    case immersivePlaybackResident
}

enum SpatialPlatformWindowResidency: Equatable, Sendable {
    case open
    case closed
}

enum SpatialPlatformResidentWindowState: Equatable, Sendable {
    case absent
    case opening
    case open
    case closing
}

struct SpatialPlatformWindowObservation {
    private struct Entry {
        let residency: SpatialPlatformWindowResidency
        let revision: UInt64
    }

    private var entries: [SpatialPlatformWindowIdentity: Entry] = [:]

    mutating func record(
        _ residency: SpatialPlatformWindowResidency,
        for window: SpatialPlatformWindowIdentity
    ) {
        entries[window] = Entry(
            residency: residency,
            revision: revision(for: window) &+ 1
        )
    }

    func residency(
        for window: SpatialPlatformWindowIdentity
    ) -> SpatialPlatformWindowResidency? {
        entries[window]?.residency
    }

    func revision(for window: SpatialPlatformWindowIdentity) -> UInt64 {
        entries[window]?.revision ?? 0
    }

    func confirms(
        _ residency: SpatialPlatformWindowResidency,
        for window: SpatialPlatformWindowIdentity,
        after revision: UInt64
    ) -> Bool {
        guard let entry = entries[window] else { return false }
        return entry.revision > revision && entry.residency == residency
    }
}

enum SpatialPlatformPlaybackWindowTransition: Equatable, Sendable {
    case enterImmersivePlayback(PresentationContentFamily)
    case exitImmersivePlayback(PresentationContentFamily)
    case collapseImmersivePlayback(PresentationContentFamily)
    case normalizeSpatialPlayback
}

enum SpatialPlatformPlaybackWindowAction: Equatable, Sendable {
    case pushResidentWindow
    case dismissResidentWindow
    case openMainWindow
}

enum SpatialPlatformPlaybackWindowPolicy {
    static func action(
        for transition: SpatialPlatformPlaybackWindowTransition,
        residentWindowState: SpatialPlatformResidentWindowState
    ) -> SpatialPlatformPlaybackWindowAction {
        switch transition {
        case .enterImmersivePlayback:
            .pushResidentWindow
        case .exitImmersivePlayback,
             .collapseImmersivePlayback,
             .normalizeSpatialPlayback:
            switch residentWindowState {
            case .absent:
                .openMainWindow
            case .opening, .open, .closing:
                .dismissResidentWindow
            }
        }
    }
}

/// Both ways out of Panorama land in the same retained Portal viewport, so
/// app-requested exits and system collapses refresh it alike.
enum PortalPlaybackViewportRefreshPolicy {
    static func requiresRefresh(
        for transition: SpatialPlatformPlaybackWindowTransition
    ) -> Bool {
        transition == .collapseImmersivePlayback(.panoramic)
            || transition == .exitImmersivePlayback(.panoramic)
    }
}

struct PortalPlaybackViewportRefreshState: Equatable, Sendable {
    private(set) var requestedRevision: UInt64 = 0
    private(set) var appliedRevision: UInt64 = 0

    mutating func request() -> UInt64 {
        requestedRevision &+= 1
        return requestedRevision
    }

    mutating func recordApplied(_ revision: UInt64) {
        guard revision <= requestedRevision else { return }
        appliedRevision = max(appliedRevision, revision)
    }

    func hasApplied(_ revision: UInt64) -> Bool {
        appliedRevision >= revision
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
