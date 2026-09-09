import AVFoundation
import CoreGraphics
import CoreMedia
import PlaybackCore

@MainActor
final class RendererTransferCoordinator {
    enum Phase: Equatable {
        case empty
        case active
        case preparing
        case prepared
        case cutover
        case settled
        case closing
    }

    enum TransferMode: Equatable {
        case rendererGraph
        case technicalSession
    }

    enum TransferError: Error, Equatable {
        case noActiveRenderer
        case transferPending
        case staleTransfer
    }

    enum ConsumerClaimResult: Equatable {
        case unchanged
        case granted(discarded: DiscardedConsumer?)
        case busy(PlaybackPresentation)
        case transferPending
    }

    enum DepartureKind: Equatable {
        case rendererGraph
        case technicalSession
    }

    struct TransferKey: Equatable {
        let generation: Int
        let logicalSessionID: String
        let sourceTechnicalSessionID: String
    }

    struct PreparedTechnicalSession {
        let resource: PlaybackMediaSessionDriver.SessionResource
        let speed: PlaybackModel.PlaybackSpeed
        let selectedAudioTrackID: String?
        let selectedSubtitleTrackID: String?
    }

    enum Continuity: Equatable {
        case timeline(CMTime)
        case ended(PlaybackEndedContinuity)
    }

    enum Delivery: Equatable {
        case pending(Continuity)
        case applied(Continuity)

        var continuity: Continuity {
            switch self {
            case .pending(let continuity), .applied(let continuity):
                continuity
            }
        }
    }

    struct CutoverToken: Equatable {
        let serial: UInt64
        let key: TransferKey
        let activeTechnicalSessionID: String
    }

    struct CutoverSnapshot: Equatable {
        let token: CutoverToken
        let sourcePresentation: PlaybackPresentation?
        let delivery: Delivery
    }

    struct Activation {
        let token: CutoverToken
        let activeResource: PlaybackMediaSessionDriver.SessionResource
        let continuity: Continuity
    }

    struct DiscardedConsumer: Equatable {
        let presentation: PlaybackPresentation
        let entityID: String
        let recordEpoch: Int
        let currentEpoch: Int
    }

    struct ConsumerSnapshot: Equatable {
        let presentation: PlaybackPresentation?
        let entityID: String?
        let releasedPresentation: PlaybackPresentation?
        let releasedEntityID: String?
        let rendererEpoch: Int
        let consumerEpoch: Int?
        let lastBoundEntityID: String?
        let boundVideoComponentRevision: UInt64?
    }

    struct RendererTargetBinding: Equatable {
        let previousEntityID: String?
        let currentEntityID: String
    }

    private struct Consumer {
        let presentation: PlaybackPresentation
        let entityID: String
    }

    private enum ConsumerOwnership {
        case available(released: Consumer?)
        case claimed(Consumer, epoch: Int)
    }

    private struct Active {
        var resource: PlaybackMediaSessionDriver.SessionResource
        var rendererEpoch: Int
        var consumer: ConsumerOwnership
        var lastBoundEntityID: String?
        var boundVideoComponentRevision: UInt64?
    }

    private struct Preparation {
        var active: Active
        let key: TransferKey
        let mode: TransferMode
    }

    private enum PreparedReplacement {
        case rendererGraph
        case technicalSession(PreparedTechnicalSession)
    }

    private struct Prepared {
        var active: Active
        let key: TransferKey
        let replacement: PreparedReplacement
    }

    private enum Departing {
        case rendererGraph(PlaybackMediaSessionDriver)
        case technicalSession(PlaybackMediaSessionDriver)

        var kind: DepartureKind {
            switch self {
            case .rendererGraph:
                .rendererGraph
            case .technicalSession:
                .technicalSession
            }
        }

        var driver: PlaybackMediaSessionDriver {
            switch self {
            case .rendererGraph(let driver), .technicalSession(let driver):
                driver
            }
        }
    }

    private struct Cutover {
        var active: Active
        var departing: Departing?
        let token: CutoverToken
        let sourcePresentation: PlaybackPresentation?
        var delivery: Delivery
        var naturalEndNotificationWasPublished: Bool
    }

    private struct Settled {
        var active: Active
        let departing: Departing
    }

    private struct Closing {
        var active: Active?
        let departing: Departing?
        let prepared: PreparedTechnicalSession?
        let serial: UInt64
    }

    private enum State {
        case empty
        case active(Active)
        case preparing(Preparation)
        case prepared(Prepared)
        case cutover(Cutover)
        case settled(Settled)
        case closing(Closing)
    }

    private var state = State.empty
    private var epoch = 0
    private var cutoverSerial: UInt64 = 0
    private var closingSerial: UInt64 = 0
    private var closeTask: Task<Void, Never>?

    var phase: Phase {
        switch state {
        case .empty:
            .empty
        case .active:
            .active
        case .preparing:
            .preparing
        case .prepared:
            .prepared
        case .cutover:
            .cutover
        case .settled:
            .settled
        case .closing:
            .closing
        }
    }

    var transferIsInFlight: Bool {
        switch state {
        case .preparing, .prepared, .cutover:
            true
        case .empty, .active, .settled, .closing:
            false
        }
    }

    var activeDriver: PlaybackMediaSessionDriver? {
        active?.resource.driver
    }

    var activeSessionID: String? {
        active?.resource.sessionID
    }

    var activeRenderer: AVSampleBufferVideoRenderer? {
        active?.resource.renderer
    }

    var preparedDriver: PlaybackMediaSessionDriver? {
        guard case .prepared(let prepared) = state,
              case .technicalSession(let replacement) = prepared.replacement else {
            return nil
        }
        return replacement.resource.driver
    }

    var preparedTechnicalSession: PreparedTechnicalSession? {
        guard case .prepared(let prepared) = state,
              case .technicalSession(let replacement) = prepared.replacement else {
            return nil
        }
        return replacement
    }

    var preparedTransferKey: TransferKey? {
        guard case .prepared(let prepared) = state else { return nil }
        return prepared.key
    }

    var liveTechnicalSessionCount: Int {
        drivers.reduce(0) { $0 + $1.liveTechnicalSessionCount }
    }

    var retiringTechnicalSessionCount: Int {
        drivers.reduce(0) { $0 + $1.retiringTechnicalSessionCount }
    }

    var consumerSnapshot: ConsumerSnapshot {
        guard let active else {
            return ConsumerSnapshot(
                presentation: nil,
                entityID: nil,
                releasedPresentation: nil,
                releasedEntityID: nil,
                rendererEpoch: epoch,
                consumerEpoch: nil,
                lastBoundEntityID: nil,
                boundVideoComponentRevision: nil
            )
        }
        let claimed: Consumer?
        let released: Consumer?
        let consumerEpoch: Int?
        switch active.consumer {
        case .available(let previous):
            claimed = nil
            released = previous
            consumerEpoch = nil
        case .claimed(let consumer, let claimedEpoch):
            claimed = consumer
            released = nil
            consumerEpoch = claimedEpoch
        }
        return ConsumerSnapshot(
            presentation: claimed?.presentation,
            entityID: claimed?.entityID,
            releasedPresentation: released?.presentation,
            releasedEntityID: released?.entityID,
            rendererEpoch: active.rendererEpoch,
            consumerEpoch: consumerEpoch,
            lastBoundEntityID: active.lastBoundEntityID,
            boundVideoComponentRevision: active.boundVideoComponentRevision
        )
    }

    func installActive(
        _ resource: PlaybackMediaSessionDriver.SessionResource
    ) throws {
        guard resource.driver.owns(resource) else {
            throw TransferError.noActiveRenderer
        }
        switch state {
        case .empty:
            epoch &+= 1
            state = .active(
                Active(
                    resource: resource,
                    rendererEpoch: epoch,
                    consumer: .available(released: nil),
                    lastBoundEntityID: nil,
                    boundVideoComponentRevision: nil
                )
            )
        case .active(var active) where active.resource.driver === resource.driver:
            epoch &+= 1
            active.resource = resource
            active.rendererEpoch = epoch
            state = .active(active)
        case .active, .preparing, .prepared, .cutover, .settled, .closing:
            throw TransferError.transferPending
        }
    }

    func beginTransfer(
        key: TransferKey,
        mode: TransferMode
    ) throws {
        guard case .active(let active) = state else {
            if self.active == nil {
                throw TransferError.noActiveRenderer
            }
            throw TransferError.transferPending
        }
        guard active.resource.driver.owns(active.resource) else {
            throw TransferError.noActiveRenderer
        }
        guard active.resource.sessionID == key.sourceTechnicalSessionID else {
            throw TransferError.staleTransfer
        }
        state = .preparing(
            Preparation(active: active, key: key, mode: mode)
        )
    }

    func finishRendererGraphPreparation(key: TransferKey) throws {
        guard case .preparing(let preparation) = state,
              preparation.key == key,
              preparation.mode == .rendererGraph else {
            throw TransferError.staleTransfer
        }
        state = .prepared(
            Prepared(
                active: preparation.active,
                key: key,
                replacement: .rendererGraph
            )
        )
    }

    func finishTechnicalSessionPreparation(
        key: TransferKey,
        replacement: PreparedTechnicalSession
    ) throws {
        guard case .preparing(let preparation) = state,
              preparation.key == key,
              preparation.mode == .technicalSession,
              replacement.resource.driver.owns(replacement.resource),
              preparation.active.resource.driver !== replacement.resource.driver,
              preparation.active.resource.renderer !== replacement.resource.renderer,
              preparation.active.resource.sessionID != replacement.resource.sessionID else {
            throw TransferError.staleTransfer
        }
        state = .prepared(
            Prepared(
                active: preparation.active,
                key: key,
                replacement: .technicalSession(replacement)
            )
        )
    }

    func activateTechnicalSession(
        key: TransferKey,
        cutoverTime: CMTime,
        endedContinuity: PlaybackEndedContinuity?,
        sourcePresentation: PlaybackPresentation?,
        naturalEndNotificationWasPublished: Bool,
        beforeCutover: () -> Void
    ) throws -> Activation {
        guard case .prepared(let prepared) = state,
              prepared.key == key,
              prepared.active.resource.sessionID == key.sourceTechnicalSessionID,
              prepared.active.resource.driver.owns(prepared.active.resource),
              case .technicalSession(let replacement) = prepared.replacement,
              replacement.resource.driver.owns(replacement.resource) else {
            throw TransferError.staleTransfer
        }
        beforeCutover()
        var source = prepared.active
        releaseConsumerForCutover(&source)
        source.resource.driver.unbindCallbacks()
        let active = replacingActive(
            source,
            with: replacement.resource
        )
        let continuity = endedContinuity.map(Continuity.ended)
            ?? .timeline(cutoverTime)
        let token = nextCutoverToken(
            key: key,
            activeTechnicalSessionID: replacement.resource.sessionID
        )
        state = .cutover(
            Cutover(
                active: active,
                departing: .technicalSession(source.resource.driver),
                token: token,
                sourcePresentation: sourcePresentation,
                delivery: .pending(continuity),
                naturalEndNotificationWasPublished:
                    naturalEndNotificationWasPublished
            )
        )
        return Activation(
            token: token,
            activeResource: replacement.resource,
            continuity: continuity
        )
    }

    func activateRendererGraph(
        key: TransferKey,
        replacement: PlaybackMediaSessionDriver.SessionResource,
        cutoverTime: CMTime,
        endedContinuity: PlaybackEndedContinuity?,
        sourcePresentation: PlaybackPresentation?,
        naturalEndNotificationWasPublished: Bool,
        beforeCutover: () -> Void
    ) throws -> Activation {
        guard case .prepared(let prepared) = state,
              prepared.key == key,
              prepared.active.resource.sessionID == key.sourceTechnicalSessionID,
              case .rendererGraph = prepared.replacement,
              replacement.driver === prepared.active.resource.driver,
              replacement.sessionID == prepared.active.resource.sessionID,
              replacement.driver.owns(replacement),
              prepared.active.resource.renderer !== replacement.renderer else {
            throw TransferError.staleTransfer
        }
        beforeCutover()
        var source = prepared.active
        releaseConsumerForCutover(&source)
        let active = replacingActive(source, with: replacement)
        let continuity = endedContinuity.map(Continuity.ended)
            ?? .timeline(cutoverTime)
        let token = nextCutoverToken(
            key: key,
            activeTechnicalSessionID: replacement.sessionID
        )
        state = .cutover(
            Cutover(
                active: active,
                departing: .rendererGraph(replacement.driver),
                token: token,
                sourcePresentation: sourcePresentation,
                delivery: .pending(continuity),
                naturalEndNotificationWasPublished:
                    naturalEndNotificationWasPublished
            )
        )
        return Activation(
            token: token,
            activeResource: replacement,
            continuity: continuity
        )
    }

    @discardableResult
    func cancelPreparedTransfer() async -> Bool {
        switch state {
        case .preparing(let preparation):
            state = reconciledState(for: preparation.active)
            return true
        case .prepared(let prepared):
            switch prepared.replacement {
            case .rendererGraph:
                state = reconciledState(for: prepared.active)
                await prepared.active.resource.driver
                    .retireDepartingVideoRendererGraph()
            case .technicalSession(let replacement):
                state = reconciledState(for: prepared.active)
                await replacement.resource.driver.close(clearSource: false)
            }
            return true
        case .empty, .active, .cutover, .settled, .closing:
            return false
        }
    }

    @discardableResult
    func abandonInstalledRendererGraph(
        key: TransferKey,
        replacement: PlaybackMediaSessionDriver.SessionResource
    ) async -> Bool {
        guard case .prepared(let prepared) = state,
              prepared.key == key,
              case .rendererGraph = prepared.replacement,
              replacement.driver === prepared.active.resource.driver,
              replacement.sessionID == prepared.active.resource.sessionID,
              replacement.driver.owns(replacement) else { return false }
        state = .active(replacingActive(prepared.active, with: replacement))
        await replacement.driver.retireDepartingVideoRendererGraph()
        return true
    }

    func cutoverSnapshot(
        generation: Int,
        logicalSessionID: String?,
        activeTechnicalSessionID: String?
    ) -> CutoverSnapshot? {
        guard case .cutover(let cutover) = state,
              cutover.token.key.generation == generation,
              cutover.token.key.logicalSessionID == logicalSessionID,
              cutover.token.activeTechnicalSessionID == activeTechnicalSessionID,
              cutover.active.resource.sessionID == activeTechnicalSessionID else {
            return nil
        }
        return snapshot(cutover)
    }

    func cutoverIsCurrent(
        _ token: CutoverToken,
        generation: Int,
        logicalSessionID: String?,
        activeTechnicalSessionID: String?
    ) -> Bool {
        guard case .cutover(let cutover) = state else { return false }
        return cutover.token == token
            && token.key.generation == generation
            && token.key.logicalSessionID == logicalSessionID
            && token.activeTechnicalSessionID == activeTechnicalSessionID
            && cutover.active.resource.sessionID == activeTechnicalSessionID
    }

    func observeEndedContinuity(
        for token: CutoverToken
    ) -> PlaybackEndedContinuity? {
        guard case .cutover(var cutover) = state,
              cutover.token == token else { return nil }
        let departingContinuity = cutover.departing?.driver.endedContinuity
        guard let continuity = departingContinuity
            ?? cutover.active.resource.driver.endedContinuity else {
            return nil
        }
        switch cutover.delivery.continuity {
        case .timeline:
            break
        case .ended(let currentContinuity):
            guard let departingContinuity,
                  currentContinuity != departingContinuity else {
                return nil
            }
        }
        cutover.delivery = .pending(.ended(continuity))
        state = .cutover(cutover)
        return continuity
    }

    func recordNaturalEndNotification(
        for token: CutoverToken,
        continuity: PlaybackEndedContinuity
    ) -> Bool {
        guard continuity.reason == .naturalCompletion,
              case .cutover(var cutover) = state,
              cutover.token == token,
              cutover.naturalEndNotificationWasPublished == false else {
            return false
        }
        cutover.naturalEndNotificationWasPublished = true
        state = .cutover(cutover)
        return true
    }

    func restartPendingDelivery(for token: CutoverToken) async throws {
        guard case .cutover(let cutover) = state,
              cutover.token == token else {
            throw TransferError.staleTransfer
        }
        guard case .pending(let continuity) = cutover.delivery else { return }
        let driver = cutover.active.resource.driver
        switch continuity {
        case .timeline(let time):
            try await driver.restartVideoSampleDelivery(at: time, after: .pause)
        case .ended(let endedContinuity):
            try await driver.restartVideoSampleDelivery(
                preserving: endedContinuity
            )
        }
        guard case .cutover(var current) = state,
              current.token == token else {
            throw TransferError.staleTransfer
        }
        if current.delivery == .pending(continuity) {
            current.delivery = .applied(continuity)
            state = .cutover(current)
        }
    }

    @discardableResult
    func retireDepartingBeforeDelivery(
        for token: CutoverToken
    ) async throws -> DepartureKind? {
        guard case .cutover(var cutover) = state,
              cutover.token == token else {
            throw TransferError.staleTransfer
        }
        guard let departing = cutover.departing,
              case .technicalSession = departing else { return nil }
        cutover.departing = nil
        state = .cutover(cutover)
        await retire(departing)
        return departing.kind
    }

    @discardableResult
    func completeCutover(_ token: CutoverToken) -> Bool {
        guard case .cutover(let cutover) = state,
              cutover.token == token else { return false }
        if let departing = cutover.departing {
            state = .settled(
                Settled(active: cutover.active, departing: departing)
            )
        } else {
            state = .active(cutover.active)
        }
        return true
    }

    @discardableResult
    func retireDepartingAfterSceneDisappearance() async -> DepartureKind? {
        let departing: Departing
        switch state {
        case .cutover(var cutover):
            guard let current = cutover.departing else { return nil }
            departing = current
            cutover.departing = nil
            state = .cutover(cutover)
        case .settled(let settled):
            departing = settled.departing
            state = .active(settled.active)
        case .empty, .active, .preparing, .prepared, .closing:
            return nil
        }
        await retire(departing)
        return departing.kind
    }

    func claimConsumer(
        presentation: PlaybackPresentation,
        entityID: String
    ) -> ConsumerClaimResult {
        var result = ConsumerClaimResult.transferPending
        mutateActive { active in
            let discarded = discardSpentConsumer(from: &active)
            switch active.consumer {
            case .claimed(let current, _):
                if current.presentation == presentation,
                   current.entityID == entityID {
                    result = .unchanged
                } else if current.entityID != entityID {
                    result = .busy(current.presentation)
                } else {
                    active.consumer = .claimed(
                        Consumer(presentation: presentation, entityID: entityID),
                        epoch: active.rendererEpoch
                    )
                    result = .granted(discarded: discarded)
                }
            case .available(let released):
                if let released,
                   permitsClaim(
                       released: released,
                       presentation: presentation,
                       entityID: entityID
                   ) == false {
                    result = .transferPending
                    return
                }
                active.consumer = .claimed(
                    Consumer(presentation: presentation, entityID: entityID),
                    epoch: active.rendererEpoch
                )
                result = .granted(discarded: discarded)
            }
        }
        return result
    }

    @discardableResult
    func releaseConsumer(
        presentation: PlaybackPresentation,
        entityID: String,
        preservingVideoComponent: Bool
    ) -> Bool {
        var released = false
        mutateActive { active in
            guard case .claimed(let current, _) = active.consumer,
                  current.presentation == presentation,
                  current.entityID == entityID else { return }
            active.consumer = .available(released: current)
            if preservingVideoComponent == false {
                active.boundVideoComponentRevision = nil
            }
            released = true
        }
        return released
    }

    func consumerIsReleased(
        from sourcePresentation: PlaybackPresentation?
    ) -> Bool {
        let snapshot = consumerSnapshot
        guard let sourcePresentation else {
            return snapshot.entityID == nil
        }
        return snapshot.presentation != sourcePresentation
    }

    func recordRendererTargetBinding(
        revision: UInt64,
        currentRevision: UInt64,
        entityID: String
    ) -> RendererTargetBinding? {
        var binding: RendererTargetBinding?
        mutateActive { active in
            guard revision == currentRevision,
                  case .claimed(let consumer, _) = active.consumer,
                  consumer.entityID == entityID else { return }
            binding = RendererTargetBinding(
                previousEntityID: active.lastBoundEntityID,
                currentEntityID: entityID
            )
            active.lastBoundEntityID = entityID
            active.boundVideoComponentRevision = revision
        }
        return binding
    }

    func rendererTargetIsCurrent(
        presentation: PlaybackPresentation,
        entityID: String,
        videoComponentRevision: UInt64
    ) -> Bool {
        guard let active else { return false }
        guard case .claimed(let consumer, _) = active.consumer else {
            return false
        }
        return active.boundVideoComponentRevision == videoComponentRevision
            && consumer.presentation == presentation
            && consumer.entityID == entityID
            && active.lastBoundEntityID == entityID
    }

    func invalidatePresentationState() {
        epoch &+= 1
        mutateActive(includingClosing: true) { active in
            active.rendererEpoch = epoch
            active.consumer = .available(released: nil)
            active.lastBoundEntityID = nil
            active.boundVideoComponentRevision = nil
        }
    }

    func resetBindingHistoryForPlaybackPreparation() {
        mutateActive { active in
            if case .available = active.consumer {
                active.consumer = .available(released: nil)
            }
            active.lastBoundEntityID = nil
            active.boundVideoComponentRevision = nil
        }
    }

    func beginClose() -> Task<Void, Never>? {
        if let closeTask { return closeTask }
        guard let closing = makeClosingState() else { return nil }
        for driver in uniqueDrivers(in: closing) {
            driver.hush()
        }
        state = .closing(closing)
        let task = Task { @MainActor [weak self] in
            await closing.active?.resource.driver.close()
            if let departing = closing.departing,
               departing.driver !== closing.active?.resource.driver {
                await departing.driver.close(clearSource: false)
            }
            if let prepared = closing.prepared,
               prepared.resource.driver !== closing.active?.resource.driver,
               prepared.resource.driver !== closing.departing?.driver {
                await prepared.resource.driver.close(clearSource: false)
            }
            self?.finishClose(serial: closing.serial)
        }
        closeTask = task
        return task
    }

    @discardableResult
    func abandonClose() -> Int {
        closeTask = nil
        guard case .closing(let closing) = state else { return 0 }
        let drivers = uniqueDrivers(in: closing)
        state = .empty
        for driver in drivers {
            driver.abandon()
        }
        return drivers.count
    }

    private var active: Active? {
        switch state {
        case .empty:
            nil
        case .active(let active):
            active
        case .preparing(let preparation):
            preparation.active
        case .prepared(let prepared):
            prepared.active
        case .cutover(let cutover):
            cutover.active
        case .settled(let settled):
            settled.active
        case .closing(let closing):
            closing.active
        }
    }

    private var drivers: [PlaybackMediaSessionDriver] {
        let values: [PlaybackMediaSessionDriver]
        switch state {
        case .empty:
            values = []
        case .active(let active):
            values = [active.resource.driver]
        case .preparing(let preparation):
            values = [preparation.active.resource.driver]
        case .prepared(let prepared):
            switch prepared.replacement {
            case .rendererGraph:
                values = [prepared.active.resource.driver]
            case .technicalSession(let replacement):
                values = [
                    prepared.active.resource.driver,
                    replacement.resource.driver
                ]
            }
        case .cutover(let cutover):
            values = [cutover.active.resource.driver]
                + [cutover.departing?.driver].compactMap(\.self)
        case .settled(let settled):
            values = [
                settled.active.resource.driver,
                settled.departing.driver
            ]
        case .closing(let closing):
            values = uniqueDrivers(in: closing)
        }
        var identifiers = Set<ObjectIdentifier>()
        return values.filter {
            identifiers.insert(ObjectIdentifier($0)).inserted
        }
    }

    private func mutateActive(
        includingClosing: Bool = false,
        _ mutation: (inout Active) -> Void
    ) {
        switch state {
        case .active(var active):
            mutation(&active)
            state = .active(active)
        case .preparing(var preparation):
            mutation(&preparation.active)
            state = .preparing(preparation)
        case .prepared(var prepared):
            mutation(&prepared.active)
            state = .prepared(prepared)
        case .cutover(var cutover):
            mutation(&cutover.active)
            state = .cutover(cutover)
        case .settled(var settled):
            mutation(&settled.active)
            state = .settled(settled)
        case .closing(var closing) where includingClosing:
            guard var active = closing.active else { return }
            mutation(&active)
            closing.active = active
            state = .closing(closing)
        case .empty, .closing:
            break
        }
    }

    private func replacingActive(
        _ source: Active,
        with resource: PlaybackMediaSessionDriver.SessionResource
    ) -> Active {
        epoch &+= 1
        return Active(
            resource: resource,
            rendererEpoch: epoch,
            consumer: .available(released: nil),
            lastBoundEntityID: nil,
            boundVideoComponentRevision: nil
        )
    }

    private func reconciledState(for source: Active) -> State {
        guard let resource = source.resource.driver.attachedResource() else {
            return .empty
        }
        guard resource.renderer !== source.resource.renderer else {
            return .active(source)
        }
        return .active(replacingActive(source, with: resource))
    }

    private func releaseConsumerForCutover(_ active: inout Active) {
        if case .claimed(let consumer, _) = active.consumer {
            active.resource.driver.recordRealityKitBinding(
                entityIdentity: consumer.entityID,
                active: false
            )
        }
        active.consumer = .available(released: nil)
        active.lastBoundEntityID = nil
        active.boundVideoComponentRevision = nil
    }

    private func discardSpentConsumer(
        from active: inout Active
    ) -> DiscardedConsumer? {
        guard case .claimed(let consumer, let consumerEpoch) = active.consumer,
              consumerEpoch != active.rendererEpoch else { return nil }
        active.consumer = .available(released: nil)
        active.lastBoundEntityID = nil
        active.boundVideoComponentRevision = nil
        return DiscardedConsumer(
            presentation: consumer.presentation,
            entityID: consumer.entityID,
            recordEpoch: consumerEpoch,
            currentEpoch: active.rendererEpoch
        )
    }

    private func permitsClaim(
        released: Consumer,
        presentation: PlaybackPresentation,
        entityID: String
    ) -> Bool {
        released.entityID == entityID
            || released.presentation.usesImmersiveSpace
                != presentation.usesImmersiveSpace
    }

    private func nextCutoverToken(
        key: TransferKey,
        activeTechnicalSessionID: String
    ) -> CutoverToken {
        cutoverSerial &+= 1
        return CutoverToken(
            serial: cutoverSerial,
            key: key,
            activeTechnicalSessionID: activeTechnicalSessionID
        )
    }

    private func snapshot(_ cutover: Cutover) -> CutoverSnapshot {
        CutoverSnapshot(
            token: cutover.token,
            sourcePresentation: cutover.sourcePresentation,
            delivery: cutover.delivery
        )
    }

    private func retire(_ departing: Departing) async {
        switch departing {
        case .rendererGraph(let driver):
            await driver.retireDepartingVideoRendererGraph()
        case .technicalSession(let driver):
            await driver.close(clearSource: false)
        }
    }

    private func makeClosingState() -> Closing? {
        let active: Active?
        let departing: Departing?
        let prepared: PreparedTechnicalSession?
        switch state {
        case .empty:
            return nil
        case .active(let current):
            active = current
            departing = nil
            prepared = nil
        case .preparing(let preparation):
            active = preparation.active
            departing = nil
            prepared = nil
        case .prepared(let current):
            active = current.active
            departing = nil
            if case .technicalSession(let replacement) = current.replacement {
                prepared = replacement
            } else {
                prepared = nil
            }
        case .cutover(let current):
            active = current.active
            departing = current.departing
            prepared = nil
        case .settled(let current):
            active = current.active
            departing = current.departing
            prepared = nil
        case .closing:
            return nil
        }
        closingSerial &+= 1
        var invalidatedActive = active
        epoch &+= 1
        invalidatedActive?.rendererEpoch = epoch
        invalidatedActive?.consumer = .available(released: nil)
        invalidatedActive?.lastBoundEntityID = nil
        invalidatedActive?.boundVideoComponentRevision = nil
        return Closing(
            active: invalidatedActive,
            departing: departing,
            prepared: prepared,
            serial: closingSerial
        )
    }

    private func uniqueDrivers(
        in closing: Closing
    ) -> [PlaybackMediaSessionDriver] {
        let values = [
            closing.active?.resource.driver,
            closing.departing?.driver,
            closing.prepared?.resource.driver
        ].compactMap(\.self)
        var identifiers = Set<ObjectIdentifier>()
        return values.filter {
            identifiers.insert(ObjectIdentifier($0)).inserted
        }
    }

    private func finishClose(serial: UInt64) {
        guard case .closing(let closing) = state,
              closing.serial == serial else { return }
        state = .empty
        closeTask = nil
    }
}

extension RendererTransferCoordinator {
    var hasActiveDriver: Bool { activeDriver != nil }

    var inFlightTransferKey: TransferKey? {
        switch state {
        case .preparing(let preparation):
            preparation.key
        case .prepared(let prepared):
            prepared.key
        default:
            nil
        }
    }

    func isActive(_ driver: PlaybackMediaSessionDriver) -> Bool {
        activeDriver === driver
    }

    func isPrepared(_ driver: PlaybackMediaSessionDriver) -> Bool {
        preparedDriver === driver
    }

    func driverForOpen(
        openingDriver: inout PlaybackMediaSessionDriver?,
        bindIfCreated: (PlaybackMediaSessionDriver) -> Void
    ) -> PlaybackMediaSessionDriver {
        if let driver = activeDriver {
            return driver
        }
        if let driver = openingDriver {
            return driver
        }
        let driver = PlaybackMediaSessionDriver()
        openingDriver = driver
        bindIfCreated(driver)
        return driver
    }

    func beginTransfer(
        generation: Int,
        logicalSessionID: String,
        sourceTechnicalSessionID: String,
        mode: TransferMode
    ) throws {
        try beginTransfer(
            key: TransferKey(
                generation: generation,
                logicalSessionID: logicalSessionID,
                sourceTechnicalSessionID: sourceTechnicalSessionID
            ),
            mode: mode
        )
    }

    func finishRendererGraphPreparation(
        generation: Int,
        logicalSessionID: String,
        sourceTechnicalSessionID: String
    ) throws {
        try finishRendererGraphPreparation(
            key: TransferKey(
                generation: generation,
                logicalSessionID: logicalSessionID,
                sourceTechnicalSessionID: sourceTechnicalSessionID
            )
        )
    }

    func applyToActiveAndPreparedDrivers(
        _ body: (PlaybackMediaSessionDriver) -> Void
    ) {
        if let driver = activeDriver {
            body(driver)
        }
        if let driver = preparedDriver {
            body(driver)
        }
    }

    func debugSnapshot() -> PlaybackDebugSnapshotV1? {
        activeDriver?.debugSnapshot()
    }

    func preparedDebugSnapshot() -> PlaybackDebugSnapshotV1? {
        preparedDriver?.debugSnapshot()
    }

    func displayedArtworkImage() -> CGImage? {
        activeDriver?.displayedArtworkImage()
    }

    func sessionForVerification() -> SampleBufferPlaybackSession? {
        activeDriver?.sessionForVerification()
    }

    func currentTime() -> CMTime? {
        activeDriver?.currentTime()
    }

    var endedContinuity: PlaybackEndedContinuity? {
        activeDriver?.endedContinuity
    }

    var availableAudioTracks: [PlaybackAudioTrack] {
        activeDriver?.availableAudioTracks ?? []
    }

    var availableSubtitleTracks: [PlaybackSubtitleTrack] {
        activeDriver?.availableSubtitleTracks ?? []
    }

    var selectedAudioStreamIndex: Int? {
        activeDriver?.selectedAudioStreamIndex
    }

    var selectedSubtitleTrackID: PlaybackSubtitleTrack.ID? {
        activeDriver?.selectedSubtitleTrackID
    }

    var activeSubtitleCues: [PlaybackSubtitleCue] {
        activeDriver?.activeSubtitleCues ?? []
    }

    var activeSubtitleFrame: PlaybackSubtitleFrame? {
        activeDriver?.activeSubtitleFrame
    }

    var activeDriverSessionID: String? {
        activeDriver?.sessionID
    }

    func setRate(_ rate: Float) throws {
        try requireActiveDriver().setRate(rate)
    }

    func setVolume(_ volume: Float) throws {
        try requireActiveDriver().setVolume(volume)
    }

    func setMuted(_ muted: Bool) throws {
        try requireActiveDriver().setMuted(muted)
    }

    func play() throws {
        try requireActiveDriver().play()
    }

    func pause() throws {
        try requireActiveDriver().pause()
    }

    func start() throws {
        try requireActiveDriver().start()
    }

    func presentationDidAttach() throws {
        try requireActiveDriver().presentationDidAttach()
    }

    func audioOnlyPresentationDidBecomeReady() throws {
        try requireActiveDriver().audioOnlyPresentationDidBecomeReady()
    }

    func playWithExternallyManagedFirstVideoFrameDeadline() throws {
        try requireActiveDriver().playWithExternallyManagedFirstVideoFrameDeadline()
    }

    func playAndVerifyRendererGraphContinuity() async throws
        -> RendererGraphPlaybackContinuity {
        try await requireActiveDriver().playAndVerifyRendererGraphContinuity()
    }

    func waitUntilTimelineReadyForControl() async throws {
        try await requireActiveDriver().waitUntilTimelineReadyForControl()
    }

    func seek(
        to time: CMTime,
        after intent: PlaybackAfterSeekIntent
    ) async throws {
        try await requireActiveDriver().seek(to: time, after: intent)
    }

    func seek(
        to time: CMTime,
        after behavior: PlaybackAfterSeekBehavior
    ) async throws {
        try await requireActiveDriver().seek(to: time, after: behavior)
    }

    func seek(
        by offset: CMTime,
        after intent: PlaybackAfterSeekIntent
    ) async throws {
        try await requireActiveDriver().seek(by: offset, after: intent)
    }

    func stepFrames(by delta: Int) async throws -> CMTime {
        try await requireActiveDriver().stepFrames(by: delta)
    }

    func selectAudioTrack(streamIndex: Int) async throws {
        try await requireActiveDriver().selectAudioTrack(streamIndex: streamIndex)
    }

    func selectSubtitleTrack(id: PlaybackSubtitleTrack.ID?) async throws {
        try await requireActiveDriver().selectSubtitleTrack(id: id)
    }

    func addExternalSubtitleSource(
        _ source: PlaybackExternalSubtitleSource
    ) async throws -> [PlaybackSubtitleTrack] {
        try await requireActiveDriver().addExternalSubtitleSource(source)
    }

    func recordRealityKitBinding(entityIdentity: String, active: Bool) {
        activeDriver?.recordRealityKitBinding(
            entityIdentity: entityIdentity,
            active: active
        )
    }

    func recordPresentationBinding(
        realityViewIdentity: String,
        platform: String,
        attached: Bool,
        sceneContainer: String,
        sceneLifecycle: String
    ) {
        activeDriver?.recordPresentationBinding(
            realityViewIdentity: realityViewIdentity,
            platform: platform,
            attached: attached,
            sceneContainer: sceneContainer,
            sceneLifecycle: sceneLifecycle
        )
    }

    func recordPresentationState(_ record: PresentationStateRecord) {
        activeDriver?.recordPresentationState(record)
    }

    func updateAudioSessionActive(_ isActive: Bool) {
        guard var record = activeDriver?.debugSnapshot()?.presentationState else { return }
        record.audioSessionActive = isActive
        activeDriver?.recordPresentationState(record)
    }

    func clearDisplayedVideoImage(forMediaSessionID mediaSessionID: String) async {
        await activeDriver?.clearDisplayedVideoImage(forMediaSessionID: mediaSessionID)
    }

    func suspendPreparedVideoSampleDelivery() async throws {
        guard let driver = preparedDriver else {
            throw TransferError.staleTransfer
        }
        try await driver.suspendVideoSampleDelivery()
    }

    func replaceActiveVideoRendererGraph() async throws
        -> PlaybackMediaSessionDriver.SessionResource {
        do {
            return try await requireActiveDriver().replaceVideoRendererGraph()
        } catch {
            _ = await cancelPreparedTransfer()
            throw error
        }
    }

    func retireActiveDepartingVideoRendererGraph() async {
        await activeDriver?.retireDepartingVideoRendererGraph()
    }

    #if DEBUG
        func debugEvidenceJSON() -> String? {
            activeDriver?.debugEvidenceJSON()
        }

        func capturePlaybackSwitchRendererState() {
            activeDriver?.capturePlaybackSwitchRendererState()
        }
    #endif

    private func requireActiveDriver() throws -> PlaybackMediaSessionDriver {
        guard let driver = activeDriver else {
            throw TransferError.noActiveRenderer
        }
        return driver
    }
}

extension PlaybackRuntime {
    public var renderer: AVSampleBufferVideoRenderer? {
        guard videoRendererIsPublished, mediaKind == .video else { return nil }
        _ = videoComponentRevision
        return rendererTransferCoordinator.activeRenderer
    }
}
