import AVFoundation
import Foundation
import Observation
import PlaybackCore
import RealityKit
import SwiftUI

struct PlaybackRealityViewHostIdentity: Equatable, Sendable, CustomStringConvertible {
    private let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }

    var description: String {
        "EnchronRealityView.spatial#\(id.uuidString)"
    }
}

enum PlaybackRealityViewTopologyWriteDecision: Equatable {
    case allowed
    case inactiveHost
    case entityOwnedByAnotherActiveHost
}

enum PlaybackRealityViewTopologyWritePolicy {
    static func decision(
        currentHostIsActive: Bool,
        entityIsActive: Bool,
        entityIsInCurrentHost: Bool
    ) -> PlaybackRealityViewTopologyWriteDecision {
        guard currentHostIsActive else { return .inactiveHost }
        guard entityIsInCurrentHost || entityIsActive == false else {
            return .entityOwnedByAnotherActiveHost
        }
        return .allowed
    }

    static func entity(_ entity: Entity, isHostedUnder root: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === root { return true }
            current = candidate.parent
        }
        return false
    }
}

public struct PlaybackRealityKitContentTypeScope: Equatable, Sendable {
    let sessionID: String
    let technicalSessionID: String

    init(
        sessionID: String,
        technicalSessionID: String? = nil
    ) {
        self.sessionID = sessionID
        self.technicalSessionID = technicalSessionID ?? sessionID
    }

    @MainActor
    init?(runtime: PlaybackRuntime) {
        guard let sessionID = runtime.activeSessionID,
              let technicalSessionID = runtime.activeTechnicalSessionID else {
            return nil
        }
        self.init(
            sessionID: sessionID,
            technicalSessionID: technicalSessionID
        )
    }
}

@MainActor
@Observable
public final class PlaybackVideoEntityStore {
    private(set) var entity = Entity()
    private(set) var departingEntity: Entity?
    let dockedInteractionSurface = PlaybackDockedInteractionSurface.makeEntity()
    let panoramaInteractionSurface = PlaybackPanoramaInteractionSurface.makeEntity()
    let windowInteractionSurface = PlaybackWindowInteractionSurface.makeEntity()
    public private(set) var realityKitContentType = "unobserved"
    private(set) var realityKitContentTypeScope: PlaybackRealityKitContentTypeScope?
    @ObservationIgnored private var renderer: AVSampleBufferVideoRenderer?
    @ObservationIgnored private var currentPresentation: PlaybackPresentation?
    @ObservationIgnored private var departingPresentation: PlaybackPresentation?
    @ObservationIgnored private var videoComponentRevision: UInt64 = 0
    @ObservationIgnored private var realityViewUsesImmersiveSpace: Bool?
    @ObservationIgnored public var onRealityKitContentTypeChanged: ((
        String,
        PlaybackRealityKitContentTypeScope
    ) -> Void)?

    public init() {}

    public var entityID: String {
        "EnchronVideo#\(ObjectIdentifier(entity))"
    }

    func hostedEntity(
        for presentation: PlaybackPresentation,
        during transition: PlaybackPresentationTransition?
    ) -> Entity {
        if transition?.previousPresentation == presentation,
           departingPresentation == presentation,
           let departingEntity {
            return departingEntity
        }
        return entity
    }

    func hostedEntityID(
        for presentation: PlaybackPresentation,
        during transition: PlaybackPresentationTransition?
    ) -> String {
        let hostedEntity = hostedEntity(for: presentation, during: transition)
        return "EnchronVideo#\(ObjectIdentifier(hostedEntity))"
    }

    func entity(
        for renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation = .window,
        videoComponentRevision: UInt64? = nil
    ) -> Entity {
        if presentation != .docked {
            dockedInteractionSurface.removeFromParent()
        }
        if presentation.usesMainWindow == false {
            windowInteractionSurface.removeFromParent()
        }
        let rendererChanged = self.renderer !== renderer
        if self.renderer != nil, rendererChanged {
            let retiredEntityID = entityID
            departingEntity = entity
            departingPresentation = currentPresentation
            entity = Entity()
            SurfaceInputProbes.record(
                "rendererOwnership.entityMint reason=rendererChanged"
                    + " retired=\(PlaybackRuntime.probeEntity(retiredEntityID))"
                    + " minted=\(PlaybackRuntime.probeEntity(entityID))"
                    + " presentation=\(presentation.rawValue)"
            )
        }
        self.renderer = renderer
        currentPresentation = presentation
        realityViewUsesImmersiveSpace = presentation.usesImmersiveSpace
        self.videoComponentRevision = videoComponentRevision ?? self.videoComponentRevision
        return entity
    }

    func hasApplied(
        videoComponentRevision: UInt64,
        to renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation = .window
    ) -> Bool {
        self.renderer === renderer
            && self.videoComponentRevision == videoComponentRevision
            && realityViewUsesImmersiveSpace == presentation.usesImmersiveSpace
    }

    func synchronizeRealityKitContentTypeScope(
        _ scope: PlaybackRealityKitContentTypeScope?
    ) {
        guard realityKitContentTypeScope != scope else { return }
        realityKitContentTypeScope = scope
        realityKitContentType = "unobserved"
    }

    func recordRealityKitContentType(
        _ contentType: String,
        for scope: PlaybackRealityKitContentTypeScope
    ) {
        guard realityKitContentTypeScope == scope,
              realityKitContentType != contentType else {
            return
        }
        realityKitContentType = contentType
        onRealityKitContentTypeChanged?(contentType, scope)
    }

    func recordRealityKitContentType(
        _ contentType: String,
        forTechnicalSessionID technicalSessionID: String
    ) {
        guard let scope = realityKitContentTypeScope,
              scope.technicalSessionID == technicalSessionID else {
            return
        }
        recordRealityKitContentType(contentType, for: scope)
    }

    func releasePlaybackComponent() {
        dockedInteractionSurface.removeFromParent()
        windowInteractionSurface.removeFromParent()
        entity.removeFromParent()
        entity.components.remove(VideoPlayerComponent.self)
        releaseDepartingEntity()
        renderer = nil
        currentPresentation = nil
        videoComponentRevision = 0
        realityViewUsesImmersiveSpace = nil
        synchronizeRealityKitContentTypeScope(nil)
    }

    func releasePlaybackComponentForRealityViewTransfer() {
        dockedInteractionSurface.removeFromParent()
        windowInteractionSurface.removeFromParent()
        entity.removeFromParent()
        entity.components.remove(VideoPlayerComponent.self)
    }

    func releaseDepartingEntity() {
        if dockedInteractionSurface.parent === departingEntity {
            dockedInteractionSurface.removeFromParent()
        }
        if windowInteractionSurface.parent === departingEntity {
            windowInteractionSurface.removeFromParent()
        }
        departingEntity?.removeFromParent()
        departingEntity?.components.remove(VideoPlayerComponent.self)
        departingEntity = nil
        departingPresentation = nil
    }
}

@MainActor
final class PlaybackSurfaceActivation {
    private var subscription: EventSubscription?
    private var retryTask: Task<Void, Never>?
    private var observedEntityID: ObjectIdentifier?
    private var onActivate: (@MainActor () -> Void)?

    static let maximumRetryCountForView = 120
    static let retryIntervalForView = Duration.milliseconds(25)

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        in content: Content,
        onActivate: @escaping @MainActor () -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        var shouldRequestRetry = false
        if observedEntityID != nextEntityID {
            cancel()
            observedEntityID = nextEntityID
            shouldRequestRetry = true
        }
        self.onActivate = onActivate
        if subscription == nil {
            subscription = content.subscribe(
                to: SceneEvents.DidActivateEntity.self,
                on: entity
            ) { [weak self] event in
                guard event.entity === entity else { return }
                Task { @MainActor [weak self] in
                    self?.onActivate?()
                    self?.requestRetry()
                }
            }
            shouldRequestRetry = true
        }
        if shouldRequestRetry {
            requestRetry()
        }
    }

    func requestRetry() {
        guard retryTask == nil, onActivate != nil else { return }
        retryTask = Task { @MainActor [weak self] in
            for _ in 0..<Self.maximumRetryCountForView {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.onActivate?()
                try? await Task.sleep(for: Self.retryIntervalForView)
            }
            self?.retryTask = nil
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
        retryTask?.cancel()
        retryTask = nil
        observedEntityID = nil
        onActivate = nil
    }
}

@MainActor
public enum PlaybackSurfaceInputAction {
    public enum Source {
        case windowSwiftUI
        case immersiveSwiftUI
        case spatialTap
        case accessibilityActivate
    }

    public static func perform(
        _ source: Source,
        appModel: PlaybackSessionModel,
        at date: Date = Date()
    ) {
        _ = source
        appModel.toggleControlsFromPlaybackSurface(at: date)
    }
}

@MainActor
enum PlaybackSurfaceInputOwner: Equatable {
    case windowInteractionSurface
    case dockedInteractionSurface
    case panoramaInteractionSurface
}

@MainActor
enum PlaybackSurfaceInputOwnership {
    static func owner(
        for presentation: PlaybackPresentation
    ) -> PlaybackSurfaceInputOwner {
        switch presentation {
        case .window, .portal:
            .windowInteractionSurface
        case .docked:
            .dockedInteractionSurface
        case .panorama:
            .panoramaInteractionSurface
        }
    }

    static func acceptsSpatialTapTarget(
        _ entity: Entity,
        for presentation: PlaybackPresentation
    ) -> Bool {
        switch owner(for: presentation) {
        case .windowInteractionSurface:
            PlaybackWindowInteractionSurface.contains(entity)
        case .dockedInteractionSurface:
            PlaybackDockedInteractionSurface.contains(entity)
        case .panoramaInteractionSurface:
            PlaybackPanoramaInteractionSurface.contains(entity)
        }
    }
}

@MainActor
enum PlaybackSurfaceAccessibility {
    static let label: LocalizedStringResource = "Playback surface"

    static func install(on entity: Entity) {
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = label
        accessibility.traits = [.button]
        accessibility.systemActions = [.activate]
        entity.components.set(accessibility)
    }
}

@MainActor
public enum PlaybackWindowInteractionSurface {
    static let entityName = "EnchronWindowInput.surface"
    static let fallbackScreenSize = SIMD2<Float>(16.0 / 9.0, 1)
    public static let thickness: Float = 0.01
    static let frontOffset: Float = 0.01

    static func makeEntity() -> Entity {
        let entity = Entity()
        configure(
            entity,
            screenSize: fallbackScreenSize,
            verticalFill: 1,
            occlusion: .none
        )
        return entity
    }

    static func install(
        _ interactionSurface: Entity,
        on videoEntity: Entity,
        screenSize: SIMD2<Float>,
        verticalFill: Float,
        occlusion: PlaybackWindowChromeOcclusion
    ) {
        configure(
            interactionSurface,
            screenSize: screenSize,
            verticalFill: verticalFill,
            occlusion: occlusion
        )
        if interactionSurface.parent !== videoEntity {
            videoEntity.addChild(interactionSurface)
        }
    }

    static func configure(
        _ entity: Entity,
        screenSize: SIMD2<Float>,
        verticalFill: Float,
        occlusion: PlaybackWindowChromeOcclusion
    ) {
        entity.name = entityName
        entity.orientation = .init()
        entity.scale = .one
        guard let region = WindowPlaybackSurfaceGeometry.interactionRegion(
            screenSize: screenSize,
            verticalFill: verticalFill,
            occlusion: occlusion,
            thickness: thickness,
            frontOffset: frontOffset
        ) else {
            entity.position = [0, 0, frontOffset]
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
            entity.components.remove(AccessibilityComponent.self)
            return
        }
        entity.position = region.center
        entity.components.set(InputTargetComponent())
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: region.size)])
        )
        PlaybackSurfaceAccessibility.install(on: entity)
    }

    static func contains(_ entity: Entity) -> Bool {
        entity.name == entityName
    }
}

@MainActor
enum PlaybackDockedInteractionSurface {
    static let entityName = "EnchronDockedInput.surface"
#if DEBUG
    static let anchorFrontProbeName = "EnchronDockedInput.probeFront"
    static let childFrontProbeName = "EnchronDockedInput.probeChildFront"
#endif
    static let fallbackScreenSize = SIMD2<Float>(16.0 / 9.0, 1)
    static let thickness: Float = 0.01
    static let frontOffset: Float = 0.01

    static func makeEntity() -> Entity {
        let entity = Entity()
        configure(entity, screenSize: fallbackScreenSize)
        return entity
    }

    static func install(
        _ interactionSurface: Entity,
        on videoEntity: Entity,
        screenSize: SIMD2<Float>
    ) {
        configure(interactionSurface, screenSize: screenSize)
        if interactionSurface.parent !== videoEntity {
            videoEntity.addChild(interactionSurface)
        }
    }

    static func configure(
        _ entity: Entity,
        screenSize: SIMD2<Float>
    ) {
        let size = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : fallbackScreenSize
        entity.name = entityName
        entity.position = [0, 0, frontOffset]
        entity.orientation = .init()
        entity.scale = .one
        entity.components.set(InputTargetComponent())
        entity.components.set(
            CollisionComponent(
                shapes: [.generateBox(size: [size.x, size.y, thickness])]
            )
        )
        PlaybackSurfaceAccessibility.install(on: entity)
    }

    static func contains(_ entity: Entity) -> Bool {
        entity.name == entityName
    }
}

@MainActor
enum PlaybackPanoramaInteractionSurface {
    static let entityNamePrefix = "EnchronPanoramaInput."

    private enum Coverage: String {
        case front180
        case full360
    }

    private struct PanelConfiguration {
        let name: String
        let position: SIMD3<Float>
        let orientation: simd_quatf
        let size: SIMD3<Float>
    }

    static func makeEntity() -> Entity {
        let root = Entity()
        configure(
            root,
            projection: .equirectangular360,
            horizontalFieldOfViewDegrees: 360
        )
        return root
    }

    static let shellRadius: Float = 8

    static func configure(
        _ root: Entity,
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int
    ) {
        let coverage: Coverage = switch projection {
        case .equirectangular180:
            .front180
        case .customAngle where horizontalFieldOfViewDegrees <= 180:
            .front180
        case .flat, .customAngle, .equirectangular360:
            .full360
        }
        let configuredName = "EnchronPanoramaInput.\(coverage.rawValue)"
        guard root.name != configuredName else { return }
        for child in Array(root.children) {
            child.removeFromParent()
        }
        root.name = configuredName

        let distance = shellRadius
        let extent = distance * 2
        let thickness: Float = 0.01
        let fullPanels: [PanelConfiguration] = [
            .init(
                name: "front",
                position: [0, 0, -distance],
                orientation: .init(),
                size: [extent, extent, thickness]
            ),
            .init(
                name: "back",
                position: [0, 0, distance],
                orientation: .init(),
                size: [extent, extent, thickness]
            ),
            .init(
                name: "left",
                position: [-distance, 0, 0],
                orientation: .init(angle: .pi / 2, axis: [0, 1, 0]),
                size: [extent, extent, thickness]
            ),
            .init(
                name: "right",
                position: [distance, 0, 0],
                orientation: .init(angle: .pi / 2, axis: [0, 1, 0]),
                size: [extent, extent, thickness]
            ),
            .init(
                name: "ceiling",
                position: [0, distance, 0],
                orientation: .init(angle: .pi / 2, axis: [1, 0, 0]),
                size: [extent, extent, thickness]
            ),
            .init(
                name: "floor",
                position: [0, -distance, 0],
                orientation: .init(angle: .pi / 2, axis: [1, 0, 0]),
                size: [extent, extent, thickness]
            )
        ]
        let frontHalfPanels: [PanelConfiguration] = [
            .init(
                name: "front",
                position: [0, 0, -distance],
                orientation: .init(),
                size: [extent, extent, thickness]
            ),
            .init(
                name: "left-front",
                position: [-distance, 0, -distance / 2],
                orientation: .init(angle: .pi / 2, axis: [0, 1, 0]),
                size: [distance, extent, thickness]
            ),
            .init(
                name: "right-front",
                position: [distance, 0, -distance / 2],
                orientation: .init(angle: .pi / 2, axis: [0, 1, 0]),
                size: [distance, extent, thickness]
            ),
            .init(
                name: "ceiling-front",
                position: [0, distance, -distance / 2],
                orientation: .init(angle: .pi / 2, axis: [1, 0, 0]),
                size: [extent, distance, thickness]
            ),
            .init(
                name: "floor-front",
                position: [0, -distance, -distance / 2],
                orientation: .init(angle: .pi / 2, axis: [1, 0, 0]),
                size: [extent, distance, thickness]
            )
        ]
        let panels = coverage == .front180 ? frontHalfPanels : fullPanels
        for configuration in panels {
            let panel = Entity()
            panel.name = entityNamePrefix + configuration.name
            panel.position = configuration.position
            panel.orientation = configuration.orientation
            panel.components.set(InputTargetComponent())
            panel.components.set(
                CollisionComponent(shapes: [.generateBox(size: configuration.size)])
            )
            PlaybackSurfaceAccessibility.install(on: panel)
            root.addChild(panel)
        }
    }

    static func contains(_ entity: Entity) -> Bool {
        entity.name.hasPrefix(entityNamePrefix)
    }
}

@MainActor
final class PlaybackSurfaceAccessibilityActivationObservation {
    private var subscription: EventSubscription?
    private var accepts: (@MainActor (Entity) -> Bool)?
    private var onActivate: (@MainActor () -> Void)?

    func observe<Content: RealityViewContentProtocol>(
        in content: Content,
        accepts: @escaping @MainActor (Entity) -> Bool,
        onActivate: @escaping @MainActor () -> Void
    ) {
        self.accepts = accepts
        self.onActivate = onActivate
        guard subscription == nil else { return }
        subscription = content.subscribe(
            to: AccessibilityEvents.Activate.self
        ) { [weak self] event in
            let entity = event.entity
            Task { @MainActor [weak self] in
                guard let self, self.accepts?(entity) == true else { return }
                self.onActivate?()
            }
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
        accepts = nil
        onActivate = nil
    }
}

@MainActor
struct PlaybackRealityViewUpdateSchedulingState {
    enum Submission: Equatable {
        case start
        case queueLatest
    }

    enum Completion: Equatable {
        case startLatest
        case idle
    }

    private var isRunning = false
    private var hasQueuedUpdate = false

    mutating func submit() -> Submission {
        guard isRunning else {
            isRunning = true
            return .start
        }
        hasQueuedUpdate = true
        return .queueLatest
    }

    mutating func complete() -> Completion {
        guard isRunning else { return .idle }
        if hasQueuedUpdate {
            hasQueuedUpdate = false
            return .startLatest
        }
        isRunning = false
        return .idle
    }

    mutating func cancel() {
        isRunning = false
        hasQueuedUpdate = false
    }
}

@MainActor
final class PlaybackRealityViewUpdateScheduler {
    typealias Operation = @MainActor () async -> Void

    private var pendingTask: Task<Void, Never>?
    private var queuedOperation: Operation?
    private var state = PlaybackRealityViewUpdateSchedulingState()
    private var generation: UInt64 = 0

    func schedule(_ operation: @escaping Operation) {
        switch state.submit() {
        case .start:
            start(operation)
        case .queueLatest:
            queuedOperation = operation
        }
    }

    private func start(_ operation: @escaping Operation) {
        let generation = self.generation
        pendingTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false,
                  self?.generation == generation else {
                return
            }
            await operation()
            guard Task.isCancelled == false,
                  let self,
                  self.generation == generation else {
                return
            }
            self.pendingTask = nil
            switch self.state.complete() {
            case .startLatest:
                guard let latest = self.queuedOperation else {
                    self.state.cancel()
                    return
                }
                self.queuedOperation = nil
                self.start(latest)
            case .idle:
                self.queuedOperation = nil
            }
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        queuedOperation = nil
        state.cancel()
        generation &+= 1
    }
}

@MainActor
final class PlaybackRendererTargetBindingGate {
    private let settlementDelay: Duration
    private var pendingTask: Task<Void, Never>?

    init(settlementDelay: Duration = .milliseconds(100)) {
        self.settlementDelay = settlementDelay
    }

    func schedule(_ operation: @escaping @MainActor () -> Void) {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settlementDelay)
            guard Task.isCancelled == false else { return }
            operation()
            pendingTask = nil
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

@MainActor
final class PlaybackVideoRendererTargetObservation {
    private var entityID: ObjectIdentifier?
    private var videoComponentRevision: UInt64?
    private var subscriptions: [EventSubscription] = []
    private(set) var targetIsAvailable = false
    private let bindingSettlement = PlaybackRendererTargetBindingGate()

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        videoComponentRevision: UInt64,
        in content: Content,
        onEvent: @escaping @MainActor (String) -> Void = { _ in },
        onTargetAvailable: @escaping @MainActor () -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard entityID != nextEntityID
                || self.videoComponentRevision != videoComponentRevision else {
            return
        }
        cancel()
        entityID = nextEntityID
        self.videoComponentRevision = videoComponentRevision

        let confirm: @Sendable (String) -> Void = { [weak self] source in
            Task { @MainActor [weak self] in
                guard let self,
                      self.entityID == nextEntityID,
                      self.videoComponentRevision == videoComponentRevision,
                      self.targetIsAvailable == false else {
                    return
                }
                onEvent("targetConfirmation source=\(source)")
                self.bindingSettlement.schedule { [weak self] in
                    guard let self,
                          self.entityID == nextEntityID,
                          self.videoComponentRevision == videoComponentRevision,
                          self.targetIsAvailable == false else {
                        return
                    }
                    self.targetIsAvailable = true
                    self.subscriptions.forEach { $0.cancel() }
                    self.subscriptions.removeAll()
                    onEvent("targetAvailable source=\(source)")
                    onTargetAvailable()
                }
            }
        }
        subscriptions = [
            content.subscribe(
                to: ComponentEvents.DidAdd.self,
                on: entity,
                componentType: VideoPlayerComponent.self
            ) { _ in
                confirm("componentDidAdd")
            },
            content.subscribe(
                to: ComponentEvents.DidChange.self,
                on: entity,
                componentType: VideoPlayerComponent.self
            ) { _ in
                confirm("componentDidChange")
            }
        ]
        confirm("observationStarted")
    }

    func cancel() {
        bindingSettlement.cancel()
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
        videoComponentRevision = nil
        targetIsAvailable = false
    }
}

@MainActor
enum PlaybackModeRecoveryAction {
    case none
    case requestModesAgain
}

@MainActor
final class PlaybackModeRequestRetry {
    static let retryWindow: TimeInterval = 3
    static let minimumRequestInterval: TimeInterval = 0.25
    static let unreportedModeWindow: TimeInterval = 8

    private var requestSignature: String?
    private var firstRequestAt: Date?
    private var lastRequestAt: Date?
    private var unreportedModeSince: Date?

    func recoveryAction(
        entity _: Entity,
        presentation: PlaybackPresentation,
        desiredImmersiveViewingMode: String,
        actualImmersiveViewingMode: String?,
        desiredSpatialVideoMode: String,
        actualSpatialVideoMode: String?,
        contentTypeMatchesProjection: Bool = true,
        requiresImmersiveViewingModeSettlement: Bool = false,
        now: Date = Date()
    ) -> PlaybackModeRecoveryAction {
        if actualImmersiveViewingMode == nil {
            let startedAt = unreportedModeSince ?? now
            guard now.timeIntervalSince(startedAt) >= Self.unreportedModeWindow else {
                unreportedModeSince = startedAt
                return .none
            }
            unreportedModeSince = now
            requestSignature = nil
        } else {
            unreportedModeSince = nil
        }
        let immersiveModeNeedsAnotherRequest = actualImmersiveViewingMode
            .map { $0 != desiredImmersiveViewingMode }
            ?? true
        let spatialVideoModeNeedsAnotherRequest = actualSpatialVideoMode
            != desiredSpatialVideoMode
        guard spatialVideoModeNeedsAnotherRequest
                || immersiveModeNeedsAnotherRequest else {
            reset()
            return .none
        }

        let nextSignature = [
            presentation.rawValue,
            desiredImmersiveViewingMode,
            desiredSpatialVideoMode
        ].joined(separator: "|")
        if requestSignature != nextSignature {
            requestSignature = nextSignature
            firstRequestAt = now
            lastRequestAt = nil
        }

        guard let firstRequestAt,
              now.timeIntervalSince(firstRequestAt) <= Self.retryWindow else {
            return .none
        }
        if let lastRequestAt,
           now.timeIntervalSince(lastRequestAt) < Self.minimumRequestInterval {
            return .none
        }
        self.lastRequestAt = now
        return .requestModesAgain
    }

    func reset() {
        requestSignature = nil
        firstRequestAt = nil
        lastRequestAt = nil
        unreportedModeSince = nil
    }
}

@MainActor
enum PlaybackRealityPresenter {
    static func configure(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation,
        requestsSpatialVideoMode: Bool,
        requestsProgressiveImmersiveViewingMode: Bool = false
    ) {
        entity.components.remove(ModelComponent.self)
        configureVideoPlayer(
            entity,
            renderer: renderer,
            presentation: presentation,
            requestsSpatialVideoMode: requestsSpatialVideoMode,
            requestsProgressiveImmersiveViewingMode:
                requestsProgressiveImmersiveViewingMode
        )
        if presentation.usesMainWindow {
            entity.components.set(
                ModelSortGroupComponent(
                    group: .planarUIInline,
                    order: WindowPlaybackSurfaceGeometry.backgroundSortOrder
                )
            )
        } else {
            entity.components.remove(ModelSortGroupComponent.self)
        }
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(AccessibilityComponent.self)
    }

    static func isBound(
        _ entity: Entity,
        to renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation
    ) -> Bool {
        entity.components[VideoPlayerComponent.self]?.videoRenderer === renderer
    }

    static func releaseVideoRenderer(from entity: Entity) {
        entity.components.remove(VideoPlayerComponent.self)
    }

    static func setOpacity(
        of entity: Entity,
        to opacity: Float,
        animated: Bool
    ) {
        guard let current = entity.components[OpacityComponent.self] else {
            entity.components.set(OpacityComponent(opacity: opacity))
            return
        }
        guard current.opacity != opacity else { return }
        guard animated else {
            entity.components.set(OpacityComponent(opacity: opacity))
            return
        }
        Entity.animate(
            PlaybackPresentationTransitionAppearance.animation(
                for: Double(opacity)
            )
        ) {
            entity.components[OpacityComponent.self]?.opacity = opacity
        }
    }

    static func reapplyDesiredModesAfterSceneActivation(
        _ entity: Entity,
        presentation: PlaybackPresentation,
        requestsSpatialVideoMode: Bool,
        requestsProgressiveImmersiveViewingMode: Bool = false
    ) {
        guard var component = entity.components[VideoPlayerComponent.self] else { return }
        component.desiredImmersiveViewingMode = immersiveViewingMode(
            for: presentation,
            requestsProgressiveImmersiveViewingMode:
                requestsProgressiveImmersiveViewingMode
        )
        component.desiredSpatialVideoMode = requestsSpatialVideoMode ? .spatial : .screen
        entity.components.set(component)
    }

    private static func configureVideoPlayer(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation,
        requestsSpatialVideoMode: Bool,
        requestsProgressiveImmersiveViewingMode: Bool
    ) {
        if var component = entity.components[VideoPlayerComponent.self],
           component.videoRenderer === renderer {
            var needsUpdate = false
            let requestedImmersiveViewingMode = immersiveViewingMode(
                for: presentation,
                requestsProgressiveImmersiveViewingMode:
                    requestsProgressiveImmersiveViewingMode
            )
            needsUpdate = needsUpdate
                || component.desiredImmersiveViewingMode != requestedImmersiveViewingMode
            component.desiredImmersiveViewingMode = requestedImmersiveViewingMode
            let requestedSpatialVideoMode: VideoPlayerComponent.SpatialVideoMode =
                requestsSpatialVideoMode ? .spatial : .screen
            needsUpdate = needsUpdate
                || component.desiredSpatialVideoMode != requestedSpatialVideoMode
            component.desiredSpatialVideoMode = requestedSpatialVideoMode
            if needsUpdate {
                entity.components.set(component)
            }
            return
        }
        var component = VideoPlayerComponent(videoRenderer: renderer)
        component.desiredImmersiveViewingMode = immersiveViewingMode(
            for: presentation,
            requestsProgressiveImmersiveViewingMode:
                requestsProgressiveImmersiveViewingMode
        )
        component.desiredSpatialVideoMode = requestsSpatialVideoMode ? .spatial : .screen
        entity.components.set(component)
    }

    private static func immersiveViewingMode(
        for presentation: PlaybackPresentation,
        requestsProgressiveImmersiveViewingMode: Bool
    ) -> VideoPlayerComponent.ImmersiveViewingMode {
        presentation == .panorama
            || requestsProgressiveImmersiveViewingMode
            ? .progressive
            : .portal
    }
}

struct PlaybackSubtitleLayout: Equatable {
    let size: SIMD2<Float>
    let position: SIMD3<Float>
}

enum PlaybackSubtitlePlacement {
    static let panoramaScreenSize = SIMD2<Float>(16.0 / 9.0 * 1.6, 1.6)
    static let panoramaScreenCenter = SIMD3<Float>(0, -0.3, -3)
    static let planeLift: Float = 0.015

    static func resolve(
        frame: PlaybackSubtitleFrame,
        presentation: PlaybackPresentation,
        screenSize: SIMD2<Float>,
        reservedBottomFraction: Float
    ) -> PlaybackSubtitleLayout {
        let resolvedScreenSize: SIMD2<Float>
        let screenCenter: SIMD3<Float>
        if presentation == .panorama {
            resolvedScreenSize = panoramaScreenSize
            screenCenter = panoramaScreenCenter
        } else {
            resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
                ? screenSize
                : SIMD2<Float>(16.0 / 9.0, 1)
            screenCenter = [0, 0, planeLift]
        }
        let canvasWidth = Float(frame.canvasWidth)
        let canvasHeight = Float(frame.canvasHeight)
        let contentWidth = resolvedScreenSize.x * Float(frame.contentWidth) / canvasWidth
        let contentHeight = resolvedScreenSize.y * Float(frame.contentHeight) / canvasHeight
        let centerX = -resolvedScreenSize.x / 2 +
            resolvedScreenSize.x * (Float(frame.contentX) + Float(frame.contentWidth) / 2) / canvasWidth
        let centerY = resolvedScreenSize.y / 2 -
            resolvedScreenSize.y * (Float(frame.contentY) + Float(frame.contentHeight) / 2) / canvasHeight
        let contentBottomY = centerY - contentHeight / 2
        let safeBottomY = -resolvedScreenSize.y / 2 +
            resolvedScreenSize.y * min(max(reservedBottomFraction, 0), 0.5)
        let safeCenterY = centerY + max(0, safeBottomY - contentBottomY)
        return PlaybackSubtitleLayout(
            size: [contentWidth, contentHeight],
            position: screenCenter + [centerX, safeCenterY, 0]
        )
    }
}

@MainActor
final class PlaybackSubtitleSurface {
    let entity = Entity()

    private var texture: TextureResource?
    private var textureSize = SIMD2<Int>(repeating: 0)
    private var changeIdentifier: UInt64?
    private var layout: PlaybackSubtitleLayout?

    func update(
        on videoEntity: Entity,
        presentation: PlaybackPresentation,
        screenSize: SIMD2<Float>,
        reservedBottomFraction: Float,
        frame: PlaybackSubtitleFrame?,
        emitEnablementWrite: (String) -> Void = { _ in }
    ) {
        guard let frame,
              frame.contentWidth > 0,
              frame.contentHeight > 0,
              frame.canvasWidth > 0,
              frame.canvasHeight > 0 else {
            if frame == nil {
                setEnabled(
                    false,
                    writer: "PlaybackSubtitleSurface.update.noFrame",
                    emit: emitEnablementWrite
                )
                changeIdentifier = nil
                layout = nil
            }
            return
        }
        let nextLayout = PlaybackSubtitlePlacement.resolve(
            frame: frame,
            presentation: presentation,
            screenSize: screenSize,
            reservedBottomFraction: reservedBottomFraction
        )
        let frameChanged = changeIdentifier != frame.changeIdentifier
        guard frameChanged || layout != nextLayout else { return }
        if frameChanged {
            guard let image = Self.image(frame) else {
                setEnabled(
                    false,
                    writer: "PlaybackSubtitleSurface.update.imageFailure",
                    emit: emitEnablementWrite
                )
                return
            }
            let nextSize = SIMD2(frame.contentWidth, frame.contentHeight)
            do {
                if let texture, textureSize == nextSize {
                    try texture.replace(
                        withImage: image,
                        options: .init(semantic: .color)
                    )
                } else {
                    texture = try TextureResource(
                        image: image,
                        options: .init(semantic: .color)
                    )
                    textureSize = nextSize
                }
            } catch {
                setEnabled(
                    false,
                    writer: "PlaybackSubtitleSurface.update.textureFailure",
                    emit: emitEnablementWrite
                )
                return
            }
        }

        guard let texture else { return }
        entity.name = "Enchron.ActiveSubtitleFrame.\(frame.kind.rawValue)"
        if frameChanged || layout?.size != nextLayout.size {
            var material = UnlitMaterial(texture: texture)
            material.blending = .transparent(opacity: .init(scale: 1))
            material.writesDepth = false
            entity.components.set(ModelComponent(
                mesh: .generatePlane(width: nextLayout.size.x, height: nextLayout.size.y),
                materials: [material]
            ))
        }
        if presentation.usesMainWindow {
            entity.components.set(
                ModelSortGroupComponent(
                    group: .planarUIInline,
                    order: WindowPlaybackSurfaceGeometry.subtitleSortOrder
                )
            )
        } else {
            entity.components.remove(ModelSortGroupComponent.self)
        }
        if entity.parent !== videoEntity {
            videoEntity.addChild(entity)
        }
        entity.position = nextLayout.position
        setEnabled(
            true,
            writer: "PlaybackSubtitleSurface.update.frameReady",
            emit: emitEnablementWrite
        )
        changeIdentifier = frame.changeIdentifier
        layout = nextLayout
    }

    func remove(emitEnablementWrite: (String) -> Void = { _ in }) {
        entity.removeFromParent()
        entity.components.remove(ModelComponent.self)
        entity.components.remove(ModelSortGroupComponent.self)
        setEnabled(
            false,
            writer: "PlaybackSubtitleSurface.remove",
            emit: emitEnablementWrite
        )
        texture = nil
        textureSize = .zero
        changeIdentifier = nil
        layout = nil
    }

    private func enablementWriteFact(writer: String, value: Bool) -> String {
        "entityEnablementWrite writer=\(writer)"
            + " entity=\(ObjectIdentifier(entity))"
            + " name=\(entity.name.isEmpty ? "unnamed" : entity.name)"
            + " value=\(value)"
            + " activeAfterWrite=\(entity.isActive)"
    }

    private func setEnabled(
        _ value: Bool,
        writer: String,
        emit: (String) -> Void
    ) {
        let previous = entity.isEnabled
        entity.isEnabled = value
        guard previous != entity.isEnabled else { return }
        emit(enablementWriteFact(writer: writer, value: value))
    }

    private static func image(_ frame: PlaybackSubtitleFrame) -> CGImage? {
        guard frame.premultipliedBGRA.count == frame.bytesPerRow * frame.contentHeight,
              let provider = CGDataProvider(data: frame.premultipliedBGRA as CFData) else {
            return nil
        }
        return CGImage(
            width: frame.contentWidth,
            height: frame.contentHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
