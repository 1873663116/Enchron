import AVFoundation
import OSLog
import PlaybackCore
import RealityKit
import RealityKitContent
import RealityKitScripting
import SwiftUI
import UIKit
import simd

@MainActor
enum EnvironmentSceneAppearanceApplier {
    static let skyboxName = "SkyDome"
    static let scenicPlaceholderName = "EnchronScenicPlaceholder"
    static let lightSkyboxOpacity: Float = 1
    static let darkSkyboxOpacity: Float = 0.35

    @discardableResult
    static func apply(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?,
        to world: Entity,
        emitEnablementWrite: (String) -> Void = { _ in }
    ) -> Float? {
        guard let skybox = world.findEntity(named: skyboxName) else {
            return nil
        }

        if environment == .skybox {
            let previous = skybox.isEnabled
            skybox.isEnabled = true
            if previous != skybox.isEnabled {
                emitEnablementWrite(
                    enablementWriteFact(
                        writer: "EnvironmentSceneAppearanceApplier.apply.skybox",
                        entity: skybox,
                        value: true
                    )
                )
            }
            skybox.components.set(OpacityComponent(opacity: 1))
            world.findEntity(named: scenicPlaceholderName)?.removeFromParent()
            return 1
        }

        let skyboxWasEnabled = skybox.isEnabled
        skybox.isEnabled = false
        if skyboxWasEnabled != skybox.isEnabled {
            emitEnablementWrite(
                enablementWriteFact(
                    writer: "EnvironmentSceneAppearanceApplier.apply.skybox",
                    entity: skybox,
                    value: false
                )
            )
        }
        let resolvedEffect = effect ?? .inactiveFallback
        let opacity = switch resolvedEffect {
        case .light: lightSkyboxOpacity
        case .dark: darkSkyboxOpacity
        }
        let color = scenicColor(for: environment, effect: resolvedEffect)
        let placeholder: ModelEntity
        if let existing = world.findEntity(named: scenicPlaceholderName) as? ModelEntity {
            placeholder = existing
            placeholder.model?.materials = [placeholderMaterial(color: color)]
        } else {
            placeholder = ModelEntity(
                mesh: .generateSphere(radius: 50),
                materials: [placeholderMaterial(color: color)]
            )
            placeholder.name = scenicPlaceholderName
            world.addChild(placeholder)
        }
        let placeholderWasEnabled = placeholder.isEnabled
        placeholder.isEnabled = true
        if placeholderWasEnabled != placeholder.isEnabled {
            emitEnablementWrite(
                enablementWriteFact(
                    writer: "EnvironmentSceneAppearanceApplier.apply.placeholder",
                    entity: placeholder,
                    value: true
                )
            )
        }
        placeholder.components.set(OpacityComponent(opacity: opacity))
        return opacity
    }

    static func clear(
        in world: Entity,
        emitEnablementWrite: (String) -> Void = { _ in }
    ) {
        if let skybox = world.findEntity(named: skyboxName) {
            let previous = skybox.isEnabled
            skybox.isEnabled = false
            if previous != skybox.isEnabled {
                emitEnablementWrite(
                    enablementWriteFact(
                        writer: "EnvironmentSceneAppearanceApplier.clear.skybox",
                        entity: skybox,
                        value: false
                    )
                )
            }
        }
        if let placeholder = world.findEntity(named: scenicPlaceholderName) {
            let previous = placeholder.isEnabled
            placeholder.isEnabled = false
            if previous != placeholder.isEnabled {
                emitEnablementWrite(
                    enablementWriteFact(
                        writer: "EnvironmentSceneAppearanceApplier.clear.placeholder",
                        entity: placeholder,
                        value: false
                    )
                )
            }
        }
    }

    private static func enablementWriteFact(
        writer: String,
        entity: Entity,
        value: Bool
    ) -> String {
        "entityEnablementWrite writer=\(writer)"
            + " entity=\(ObjectIdentifier(entity))"
            + " name=\(entity.name.isEmpty ? "unnamed" : entity.name)"
            + " value=\(value)"
            + " activeAfterWrite=\(entity.isActive)"
    }

    private static func scenicColor(
        for environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) -> UIColor {
        let components: (CGFloat, CGFloat, CGFloat) = switch environment {
        case .scenicOne: (0.86, 0.48, 0.52)
        case .scenicTwo: (0.48, 0.78, 0.58)
        case .scenicThree: (0.46, 0.66, 0.88)
        case .skybox: (0.46, 0.66, 0.88)
        }
        let brightness: CGFloat = effect == .light ? 1 : 0.46
        return UIColor(
            red: components.0 * brightness,
            green: components.1 * brightness,
            blue: components.2 * brightness,
            alpha: 1
        )
    }

    private static func placeholderMaterial(color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .front
        return material
    }
}

@MainActor
private final class WorldSceneState {
    var entity: Entity?
    var playbackSurfaceAnchor: Entity?
    var appliedEnvironment: SpatialSceneDomain.CinemaEnvironment?
    var appliedEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect?
    var isLoading = false
    var hasFailed = false
}

@MainActor
enum SpatialPresentationRefreshTrigger: CaseIterable {
    case viewingModeDidChange
    case immersiveViewingModeDidChange
    case immersiveViewingModeDidTransition
    case spatialVideoModeDidChange
    case renderingStatusDidChange
    case contentTypeDidChange
}

struct SpatialPresentationReadiness: Equatable {
    let componentIsReady: Bool
    let immersiveModeMatches: Bool
    let projectionIsAdopted: Bool
    let viewingModeMatches: Bool
    let spatialModeMatches: Bool
    let displayedPixelBuffer: Bool

    var isReadyToRevealForPixelProof: Bool {
        allNonPixelFactsAreReady && displayedPixelBuffer == false
    }

    var isSettled: Bool {
        allNonPixelFactsAreReady && displayedPixelBuffer
    }

    private var allNonPixelFactsAreReady: Bool {
        componentIsReady
            && immersiveModeMatches
            && projectionIsAdopted
            && viewingModeMatches
            && spatialModeMatches
    }
}

enum SpatialFirstFrameUpdateDriveDecision: Equatable {
    case requestUpdate
    case firstFrameArrived
    case surfaceNoLongerViable
}

enum SpatialFirstFrameUpdateDrivePolicy {
    static func decide(
        surfaceCanStillSettle: Bool,
        currentRendererHasPixels: Bool
    ) -> SpatialFirstFrameUpdateDriveDecision {
        guard surfaceCanStillSettle else { return .surfaceNoLongerViable }
        return currentRendererHasPixels ? .firstFrameArrived : .requestUpdate
    }
}

struct PortalToPanoramaRevealTarget: Equatable {
    let transitionID: UUID
    let technicalSessionID: String
    let videoComponentRevision: UInt64
    let entityID: String

    init?(
        transition: PlaybackPresentationTransition?,
        technicalSessionID: String?,
        videoComponentRevision: UInt64,
        entityID: String
    ) {
        guard let transition,
              transition.previousPresentation == .portal,
              transition.targetPresentation == .panorama,
              let technicalSessionID else {
            return nil
        }
        transitionID = transition.id
        self.technicalSessionID = technicalSessionID
        self.videoComponentRevision = videoComponentRevision
        self.entityID = entityID
    }
}

struct PortalToPanoramaTargetRevealState: Equatable {
    private(set) var revealedTarget: PortalToPanoramaRevealTarget?

    mutating func admit(
        _ target: PortalToPanoramaRevealTarget,
        when readiness: SpatialPresentationReadiness
    ) -> Bool {
        guard readiness.isReadyToRevealForPixelProof,
              revealedTarget != target else {
            return false
        }
        revealedTarget = target
        return true
    }

    func opacity(
        for target: PortalToPanoramaRevealTarget?,
        otherwise existingOpacity: Double
    ) -> Double {
        guard let target, target == revealedTarget else {
            return existingOpacity
        }
        return 1
    }
}

@MainActor
private enum SpatialPresentationChange: Equatable {
    case videoSize
    case state
}

@MainActor
private final class SpatialPresentationObservation {
    private var entityID: ObjectIdentifier?
    private var contentTypeSessionID: String?
    private var subscriptions: [EventSubscription] = []
    private let modeRequestRetry = PlaybackModeRequestRetry()
    private var lastSurfaceReadinessSignatureByReason: [String: String] = [:]
    private var lastSurfaceReadinessEmissionByReason: [String: Date] = [:]

    func observe(
        _ entity: Entity,
        in content: RealityViewContent,
        contentTypeSessionID: String?,
        onChange: @escaping @MainActor (SpatialPresentationChange) -> Void,
        onContentTypeDidChange: @escaping @MainActor (
            String,
            String
        ) -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard entityID != nextEntityID
                || self.contentTypeSessionID != contentTypeSessionID else {
            return
        }
        prepareForReplacementEntity()
        entityID = nextEntityID
        self.contentTypeSessionID = contentTypeSessionID
        subscriptions = [
            content.subscribe(to: VideoPlayerEvents.VideoSizeDidChange.self, on: entity) { _ in
                Task { @MainActor in
                    onChange(.videoSize)
                }
            },
            content.subscribe(to: VideoPlayerEvents.ViewingModeDidChange.self, on: entity) { _ in
                Task { @MainActor in
                    onChange(.state)
                }
            },
            content.subscribe(to: VideoPlayerEvents.ImmersiveViewingModeDidChange.self, on: entity) { _ in
                Task { @MainActor in
                    onChange(.state)
                }
            },
            content.subscribe(to: VideoPlayerEvents.ImmersiveViewingModeDidTransition.self, on: entity) { _ in
                Task { @MainActor in
                    onChange(.state)
                }
            },
            content.subscribe(to: VideoPlayerEvents.SpatialVideoModeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange(.state) }
            },
            content.subscribe(to: VideoPlayerEvents.RenderingStatusDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange(.state) }
            }
        ]
        if let contentTypeSessionID {
            subscriptions.append(
                content.subscribe(to: VideoPlayerEvents.ContentTypeDidChange.self) { event in
                    let contentType = String(describing: event.contentType)
                    Task { @MainActor in
                        onContentTypeDidChange(contentType, contentTypeSessionID)
                        onChange(.state)
                    }
                }
            )
        }
    }

    func prepareForReplacementEntity() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
        contentTypeSessionID = nil
        lastSurfaceReadinessSignatureByReason.removeAll()
        lastSurfaceReadinessEmissionByReason.removeAll()
    }

    func cancel() {
        prepareForReplacementEntity()
        modeRequestRetry.reset()
    }

    func shouldLogSurfaceReadiness(
        reason: String,
        signature: String,
        heartbeat: TimeInterval? = nil
    ) -> Bool {
        let now = Date()
        let signatureChanged =
            lastSurfaceReadinessSignatureByReason[reason] != signature
        let heartbeatDue = heartbeat.map { interval in
            lastSurfaceReadinessEmissionByReason[reason].map {
                now.timeIntervalSince($0) >= interval
            } ?? true
        } ?? false
        guard signatureChanged || heartbeatDue else { return false }
        lastSurfaceReadinessSignatureByReason[reason] = signature
        lastSurfaceReadinessEmissionByReason[reason] = now
        return true
    }

    func modeRecoveryAction(
        to entity: Entity,
        presentation: PlaybackPresentation,
        component: VideoPlayerComponent,
        projection: PlaybackModel.ProjectionType,
        sourceContentKind: PlaybackModel.SourceVideoContentKind,
        provenance: MediaFormatProvenance,
        observedContentType: String
    ) -> PlaybackModeRecoveryAction {
        modeRequestRetry.recoveryAction(
            entity: entity,
            presentation: presentation,
            desiredImmersiveViewingMode: String(
                describing: component.desiredImmersiveViewingMode
            ),
            actualImmersiveViewingMode: component.immersiveViewingMode.map {
                String(describing: $0)
            },
            desiredSpatialVideoMode: String(
                describing: component.desiredSpatialVideoMode
            ),
            actualSpatialVideoMode: String(describing: component.spatialVideoMode),
            contentTypeMatchesProjection: presentation != .panorama
                || SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                    projection: projection,
                    sourceContentKind: sourceContentKind,
                    provenance: provenance,
                    observedContentType: observedContentType
                )
        )
    }
}

@MainActor
private final class SpatialDisplayLinkProbe {
    private var scope: String?
    private var startedAt: Date?
    private var lastState: String?
    private var lastKnownEntityIsInRealityView: Bool?
    private var observedFirstFrame = false
    private var realityViewUpdateCount: UInt64 = 0
    private var lastRealityViewUpdateAt: Date?
    private var explicitSampleCount: UInt64 = 0
    private var lastExplicitSampleEmissionAt: Date?
    private var lastEnablementChain: String?

    func recordRealityViewUpdate(
        technicalSessionID: String?,
        renderer: AVSampleBufferVideoRenderer,
        videoComponentRevision: UInt64,
        entity: Entity,
        entityIsInRealityView: Bool,
        emit: (String) -> Void
    ) {
        prepareScopeIfNeeded(
            technicalSessionID: technicalSessionID,
            renderer: renderer,
            videoComponentRevision: videoComponentRevision,
            entity: entity,
            emit: emit
        )
        realityViewUpdateCount &+= 1
        lastRealityViewUpdateAt = Date()
        lastKnownEntityIsInRealityView = entityIsInRealityView
        emit(
            "displayLink realityViewUpdate"
                + " count=\(realityViewUpdateCount)"
                + scopeFields(
                    technicalSessionID: technicalSessionID,
                    renderer: renderer,
                    videoComponentRevision: videoComponentRevision,
                    entity: entity
                )
                + " elapsed=\(elapsed)"
                + " entityInRealityView=\(entityIsInRealityView)"
                + " enablementChain=\(enablementChain(for: entity))"
        )
    }

    func record(
        event: String,
        technicalSessionID: String?,
        renderer: AVSampleBufferVideoRenderer,
        videoComponentRevision: UInt64,
        entity: Entity,
        entityIsInRealityView: Bool?,
        targetIsAvailable: Bool,
        isExplicitFirstFrameWaitSample: Bool = false,
        emit: (String) -> Void
    ) {
        prepareScopeIfNeeded(
            technicalSessionID: technicalSessionID,
            renderer: renderer,
            videoComponentRevision: videoComponentRevision,
            entity: entity,
            emit: emit
        )

        if let entityIsInRealityView {
            lastKnownEntityIsInRealityView = entityIsInRealityView
        }

        let component = entity.components[VideoPlayerComponent.self]
        let componentRendererIdentity = component?.videoRenderer.map {
            String(describing: ObjectIdentifier($0))
        } ?? "none"
        let pixelBuffer = renderer.displayedPixelBuffer()
        let rawPixelReturn: String
        if let pixelBuffer {
            rawPixelReturn = [
                "pixelBuffer",
                "hash=\(CFHash(pixelBuffer))",
                "width=\(CVPixelBufferGetWidth(pixelBuffer))",
                "height=\(CVPixelBufferGetHeight(pixelBuffer))"
            ].joined(separator: ":")
        } else {
            rawPixelReturn = "nil"
        }
        let state = [
            "componentPresent=\(component != nil)",
            "componentRenderer=\(componentRendererIdentity)",
            "componentBound=\(component?.videoRenderer === renderer)",
            "renderingStatus=\(component.map { String(describing: $0.currentRenderingStatus) } ?? "none")",
            "entityActive=\(entity.isActive)",
            "entityParent=\(entity.parent.map { String(describing: ObjectIdentifier($0)) } ?? "none")",
            "entityInRealityView=\(lastKnownEntityIsInRealityView.map(String.init) ?? "unknown")",
            "targetAvailable=\(targetIsAvailable)",
            "displayedPixelBufferReturned=\(pixelBuffer != nil)",
            "realityViewUpdateCount=\(realityViewUpdateCount)",
            "lastRealityViewUpdateElapsed=\(lastRealityViewUpdateAt.map { $0.timeIntervalSince(startedAt ?? $0) } ?? -1)"
        ].joined(separator: ",")
        let chain = enablementChain(for: entity)
        if chain != lastEnablementChain {
            lastEnablementChain = chain
            emit(
                "displayLink entityEnablementChain"
                    + scopeFields(
                        technicalSessionID: technicalSessionID,
                        renderer: renderer,
                        videoComponentRevision: videoComponentRevision,
                        entity: entity
                    )
                    + " elapsed=\(elapsed)"
                    + " sample=\(isExplicitFirstFrameWaitSample ? "firstFrameWait" : event)"
                    + " chain=\(chain)"
            )
        }
        if isExplicitFirstFrameWaitSample {
            explicitSampleCount &+= 1
        }
        let now = Date()
        let explicitHeartbeatDue = isExplicitFirstFrameWaitSample
            && lastExplicitSampleEmissionAt.map {
                now.timeIntervalSince($0) >= 2
            } ?? true
        if state != lastState || explicitHeartbeatDue {
            lastState = state
            if isExplicitFirstFrameWaitSample {
                lastExplicitSampleEmissionAt = now
            }
            emit(
                "displayLink event=\(event)"
                    + scopeFields(
                        technicalSessionID: technicalSessionID,
                        renderer: renderer,
                        videoComponentRevision: videoComponentRevision,
                        entity: entity
                    )
                    + " elapsed=\(elapsed)"
                    + " explicitSampleCount=\(explicitSampleCount)"
                    + " displayedPixelBufferRaw=\(rawPixelReturn)"
                    + " enablementChain=\(chain)"
                    + " \(state)"
            )
        }
        if pixelBuffer != nil, observedFirstFrame == false {
            observedFirstFrame = true
            emit(
                "displayLink firstFrame"
                    + scopeFields(
                        technicalSessionID: technicalSessionID,
                        renderer: renderer,
                        videoComponentRevision: videoComponentRevision,
                        entity: entity
                    )
                    + " elapsed=\(elapsed)"
                    + " realityViewUpdateCount=\(realityViewUpdateCount)"
                    + " explicitSampleCount=\(explicitSampleCount)"
                    + " displayedPixelBufferRaw=\(rawPixelReturn)"
            )
        }
    }

    private func prepareScopeIfNeeded(
        technicalSessionID: String?,
        renderer: AVSampleBufferVideoRenderer,
        videoComponentRevision: UInt64,
        entity: Entity,
        emit: (String) -> Void
    ) {
        let nextScope = scopeFields(
            technicalSessionID: technicalSessionID,
            renderer: renderer,
            videoComponentRevision: videoComponentRevision,
            entity: entity
        )
        guard scope != nextScope else { return }
        scope = nextScope
        startedAt = Date()
        lastState = nil
        lastKnownEntityIsInRealityView = nil
        observedFirstFrame = false
        realityViewUpdateCount = 0
        lastRealityViewUpdateAt = nil
        explicitSampleCount = 0
        lastExplicitSampleEmissionAt = nil
        lastEnablementChain = nil
        emit("displayLink scopeStarted" + nextScope)
    }

    private func scopeFields(
        technicalSessionID: String?,
        renderer: AVSampleBufferVideoRenderer,
        videoComponentRevision: UInt64,
        entity: Entity
    ) -> String {
        " technicalSession=\(technicalSessionID ?? "none")"
            + " renderer=\(ObjectIdentifier(renderer))"
            + " rendererGeneration=\(videoComponentRevision)"
            + " entity=\(ObjectIdentifier(entity))"
    }

    private var elapsed: TimeInterval {
        startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    private func enablementChain(for entity: Entity) -> String {
        var fields: [String] = []
        var current: Entity? = entity
        var depth = 0
        while let candidate = current {
            fields.append(
                "\(depth):\(ObjectIdentifier(candidate))"
                    + ":\(candidate.name.isEmpty ? "unnamed" : candidate.name)"
                    + ":enabled=\(candidate.isEnabled)"
                    + ":active=\(candidate.isActive)"
            )
            current = candidate.parent
            depth += 1
        }
        return fields.joined(separator: ">")
    }

    func reset() {
        scope = nil
        startedAt = nil
        lastState = nil
        lastKnownEntityIsInRealityView = nil
        observedFirstFrame = false
        realityViewUpdateCount = 0
        lastRealityViewUpdateAt = nil
        explicitSampleCount = 0
        lastExplicitSampleEmissionAt = nil
        lastEnablementChain = nil
    }
}

public struct ImmersiveSpaceView: View {
    private static let collisionShellInputShelved = false
#if DEBUG
    private static let headInputProbeIsEnabled =
        ProcessInfo.processInfo.environment["ENCHRON_HEAD_INPUT_PROBE"] == "1"
    private static let dockedHitTestProbesAreEnabled =
        ProcessInfo.processInfo.environment["ENCHRON_DOCKED_HIT_TEST_PROBES"] == "1"
#endif

    @Environment(PlaybackSessionModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var realityViewHostIdentity = PlaybackRealityViewHostIdentity()
    @State private var realityViewHostMarker: Entity = {
        let entity = Entity()
        entity.name = "EnchronRealityView.host"
        return entity
    }()
    @State private var world = WorldSceneState()
    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var subtitleFollower = PanoramaSubtitleFollower()
    @State private var realityViewUpdateScheduler = PlaybackRealityViewUpdateScheduler()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var surfaceAccessibilityActivation =
        PlaybackSurfaceAccessibilityActivationObservation()
    @State private var rendererTargetObservation =
        PlaybackVideoRendererTargetObservation()
    @State private var presentationObservation = SpatialPresentationObservation()
    @State private var displayLinkProbe = SpatialDisplayLinkProbe()
    @State private var controlsAttachmentController =
        ImmersivePlaybackControlsAttachmentController()
    @State private var targetRevealState = PortalToPanoramaTargetRevealState()
    @State private var surfaceRefreshTick = 0
    @State private var hasRecordedCollisionShellShelved = false
#if DEBUG
    @State private var dockedAnchorFrontProbe = Entity()
    @State private var dockedChildFrontProbe = Entity()
#endif
    private let logger = Logger(subsystem: "app.enchron", category: "SpatialSurface")

    private var videoEntity: Entity {
        playbackVideoEntityStore.hostedEntity(
            for: requestedPresentation,
            during: appModel.presentationTransition
        )
    }

    private var panoramaInteractionSurface: Entity {
        playbackVideoEntityStore.panoramaInteractionSurface
    }

    private var dockedInteractionSurface: Entity {
        playbackVideoEntityStore.dockedInteractionSurface
    }

#if DEBUG
    @State private var headInputProbe: Entity = {
        let anchor = AnchorEntity(.head, trackingMode: .continuous)
        let panel = Entity()
        panel.name = "EnchronHeadInput.probe"
        panel.position = [0, 0, -2]
        panel.components.set(InputTargetComponent())
        panel.components.set(
            CollisionComponent(shapes: [.generateBox(size: [6, 6, 0.01])])
        )
        anchor.addChild(panel)
        return anchor
    }()
#endif

    private var realityKitContentTypeScope: PlaybackRealityKitContentTypeScope? {
        PlaybackRealityKitContentTypeScope(runtime: playbackRuntime)
    }

    public init() {}

    private var requestedPresentation: PlaybackPresentation {
        guard let transition = appModel.presentationTransition else {
            return appModel.playbackPresentation
        }
        if transition.previousPresentation.usesImmersiveSpace,
           transition.targetPresentation.usesMainWindow,
           appModel.presentationSourceRendererMayRelease == false {
            return transition.previousPresentation
        }
        return transition.targetPresentation
    }

    private var requestedEnvironmentContext: EnvironmentContext {
        guard let transition = appModel.presentationTransition else {
            return appModel.environmentContext
        }
        if transition.previousPresentation.usesImmersiveSpace,
           transition.targetPresentation.usesMainWindow,
           appModel.presentationSourceRendererMayRelease == false {
            return transition.previousEnvironment
        }
        return transition.targetEnvironment
    }

    public var body: some View {
        RealityView { content, attachments in
            installRealityViewHostMarker(into: content)
            scheduleSpatialSurfaceUpdate(content)
            installControlsAttachment(from: attachments, into: content)
        } update: { content, attachments in
            installRealityViewHostMarker(into: content)
            scheduleSpatialSurfaceUpdate(content)
            installControlsAttachment(from: attachments, into: content)
        } attachments: {
            Attachment(
                id: ImmersivePlaybackControlsAttachmentController.attachmentID
            ) {
                ImmersivePlaybackControlsAttachmentView(
                    presentation: requestedPresentation
                )
            }
        }
        .realityScripting()
        .simultaneousGesture(spatialSurfaceTapGesture)
        .allowsHitTesting(spatialPresentationAcceptsInput)
        .onDisappear {
            controlsAttachmentController.stop()
            realityViewUpdateScheduler.cancel()
            surfaceAccessibilityActivation.cancel()
            releaseSpatialSurface()
        }
        .task(id: spatialSurfaceReadinessKey) {
            await retrySpatialSurfaceAttachment()
        }
        .task(id: spatialFirstFrameProbeKey) {
            await sampleWhileWaitingForSpatialFirstFrame()
        }
        .onChange(of: playbackRuntime.videoComponentRevision) {
            surfaceRefreshTick &+= 1
        }
        .onChange(of: playbackRuntime.activeSubtitleFrame?.changeIdentifier) {
            refreshSubtitleSurface()
        }
        .onChange(of: spatialPresentationAcceptsInput, initial: true) { _, accepts in
            appModel.recordSurfaceInputProbe("acceptsInput=\(accepts)")
        }
        .onChange(of: immersiveControlsAreVisible, initial: true) { _, visible in
            controlsAttachmentController.setVisible(visible)
            refreshSubtitleSurface()
        }
        .onChange(of: realityKitContentTypeScope) { _, scope in
            playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(scope)
            surfaceRefreshTick &+= 1
        }
        .onChange(of: playbackRuntime.activeTechnicalSessionID) { previous, current in
            appModel.recordSurfaceInputProbe(
                "technicalSession \(previous ?? "none") -> \(current ?? "none")"
            )
        }
        .onChange(of: playbackRuntime.effectiveProjectionType) { previous, current in
            appModel.recordSurfaceInputProbe(
                "projection \(previous.rawValue) -> \(current.rawValue)"
                    + " provenance=\(playbackRuntime.activeMediaFormatProvenance.rawValue)"
                    + " lifecycle=\(playbackRuntime.productLifecycle)"
            )
        }
        .onChange(of: appModel.playbackPresentation) { previous, current in
            appModel.recordSurfaceInputProbe(
                "presentation \(previous.rawValue) -> \(current.rawValue)"
                    + " pendingEffect=\(String(describing: appModel.pendingSpatialPlatformEffect?.effect))"
            )
        }
#if DEBUG
        .onChange(of: appModel.showBlackoutProbeWindow) { _, visible in
            if visible {
                openWindow(id: "blackoutProbe")
            } else {
                dismissWindow(id: "blackoutProbe")
            }
            appModel.recordSurfaceInputProbe("blackoutProbeWindow visible=\(visible)")
        }
#endif
    }

    private func installRealityViewHostMarker(
        into content: RealityViewContent
    ) {
        guard content.entities.contains(where: { $0 === realityViewHostMarker })
                == false else {
            return
        }
        content.add(realityViewHostMarker)
    }

    private func installControlsAttachment(
        from attachments: RealityViewAttachments,
        into content: RealityViewContent
    ) {
        guard let attachment = attachments.entity(
            for: ImmersivePlaybackControlsAttachmentController.attachmentID
        ) else {
            return
        }
        if attachment.parent == nil {
            content.add(attachment)
        }
        controlsAttachmentController.attach(attachment, appModel: appModel)
    }

    private func scheduleSpatialSurfaceUpdate(
        _ content: RealityViewContent
    ) {
        let revision = surfaceRefreshTick
        let dockedPlacement = currentDockedSurfaceTransform
        let spatialPresentationOpacity = spatialPresentationOpacity
        realityViewUpdateScheduler.schedule {
            if needsWorld {
                await loadWorld(
                    into: content,
                    dockedPlacement: dockedPlacement,
                    spatialPresentationOpacity: spatialPresentationOpacity
                )
                guard Task.isCancelled == false else { return }
            }
            update(
                content,
                revision: revision,
                dockedPlacement: dockedPlacement,
                spatialPresentationOpacity: spatialPresentationOpacity
            )
        }
    }

    private var currentDockedSurfaceTransform: PlaybackSurfaceTransform {
        PlaybackSurfaceTransform(
            distance: appModel.screenDepthOffset,
            elevationDegrees: appModel.screenViewAngle,
            scale: appModel.screenScale
        )
    }

    private var needsWorld: Bool {
        requestedPresentation == .docked
            || (requestedPresentation.usesMainWindow
                && requestedEnvironmentContext.environment != nil)
    }

    private var spatialPresentationOpacity: Double {
        let existingOpacity = PlaybackPresentationTransitionAppearance.opacity(
            for: requestedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition,
            visualCutoverMayBegin: appModel.presentationVisualCutoverMayBegin
        )
        return targetRevealState.opacity(
            for: portalToPanoramaRevealTarget,
            otherwise: existingOpacity
        )
    }

    private var portalToPanoramaRevealTarget: PortalToPanoramaRevealTarget? {
        guard let transition = appModel.presentationTransition else {
            return nil
        }
        return PortalToPanoramaRevealTarget(
            transition: transition,
            technicalSessionID: playbackRuntime.activeTechnicalSessionID,
            videoComponentRevision: playbackRuntime.videoComponentRevision,
            entityID: entityID(for: transition.targetPresentation)
        )
    }

    private var spatialPresentationAcceptsInput: Bool {
        PlaybackPresentationTransitionAppearance.acceptsInput(
            for: requestedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    private var immersiveControlsAreVisible: Bool {
        ImmersivePlaybackControlsAttachmentPolicy.isVisible(
            presentation: requestedPresentation,
            controlsVisible: appModel.showControls,
            transitionIsActive: appModel.presentationTransition != nil
        )
    }

    private var spatialSurfaceTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                guard controlsAttachmentController.contains(value.entity) == false else {
                    appModel.recordSurfaceInputProbe(
                        "spatialTap entity=\(value.entity.name) accepted=false controls=true"
                    )
                    return
                }
                guard PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                    value.entity,
                    for: requestedPresentation
                ) else {
                    appModel.recordSurfaceInputProbe(
                        "spatialTap entity=\(value.entity.name) accepted=false controls=false"
                    )
                    return
                }
                appModel.recordSurfaceInputProbe(
                    "spatialTap entity=\(value.entity.name) accepted=true"
                )
                toggleControlsFromSpatialSurface(.spatialTap)
            }
    }

    private func toggleControlsFromSpatialSurface(
        _ source: PlaybackSurfaceInputAction.Source
    ) {
        withAnimation(.easeInOut(duration: 0.25)) {
            PlaybackSurfaceInputAction.perform(source, appModel: appModel)
        }
        appModel.recordSurfaceInputProbe(
            "toggle source=\(source) showControls=\(appModel.showControls)"
        )
    }

    @MainActor
    private func update(
        _ content: RealityViewContent,
        revision: Int,
        dockedPlacement: PlaybackSurfaceTransform,
        spatialPresentationOpacity: Double
    ) {
        _ = revision
        playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(
            realityKitContentTypeScope
        )
        updateWorld(in: content)
        let presentation = requestedPresentation
        if presentation.usesImmersiveSpace,
           realityViewHostMarker.isActive == false {
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                "inactiveRealityViewHost"
            )
            return
        }
        if presentation == .panorama {
            PlaybackPanoramaInteractionSurface.configure(
                panoramaInteractionSurface,
                projection: playbackRuntime.effectiveProjectionType,
                horizontalFieldOfViewDegrees:
                    playbackRuntime.effectiveHorizontalFieldOfViewDegrees
            )
        }
        updatePanoramaInteractionSurface(
            in: content,
            isActive: presentation == .panorama
        )
        guard presentation.usesImmersiveSpace else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("inactive")
            removeVideo(from: content, reason: "mainWindowPresentation")
            return
        }
        guard let renderer = playbackRuntime.renderer else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererUnavailable")
            removeVideo(from: content, reason: "rendererUnavailable")
            return
        }
        guard presentation != .docked || world.playbackSurfaceAnchor != nil else {
            let stage = if world.hasFailed {
                "worldLoadFailed"
            } else if world.isLoading {
                "loadingWorld"
            } else {
                "waitingForDockedAnchor"
            }
            appModel.recordSpatialPlaybackSurfacePreparationStage(stage)
            return
        }

        appModel.recordSpatialPlaybackSurfacePreparationStage("preparingEntity")
        presentVideo(
            in: content,
            with: renderer,
            as: presentation,
            dockedPlacement: dockedPlacement,
            spatialPresentationOpacity: spatialPresentationOpacity
        )
    }

    @MainActor
    private func updatePanoramaInteractionSurface(
        in content: RealityViewContent,
        isActive: Bool
    ) {
        if isActive {
            if Self.collisionShellInputShelved {
                if hasRecordedCollisionShellShelved == false {
                    hasRecordedCollisionShellShelved = true
                    appModel.recordSurfaceInputProbe("shellShelved")
                }
            } else {
                panoramaInteractionSurface.position = .zero
                panoramaInteractionSurface.orientation = .init()
                if content.entities.contains(where: { $0 === panoramaInteractionSurface }) == false {
                    content.add(panoramaInteractionSurface)
                    appModel.recordSurfaceInputProbe(
                        "shellAttached name=\(panoramaInteractionSurface.name)"
                            + " children=\(panoramaInteractionSurface.children.count)"
                            + " active=\(panoramaInteractionSurface.isActive)"
                    )
                }
            }
#if DEBUG
            if Self.headInputProbeIsEnabled,
               content.entities.contains(where: { $0 === headInputProbe }) == false {
                content.add(headInputProbe)
                appModel.recordSurfaceInputProbe(
                    "headProbeAttached active=\(headInputProbe.isActive)"
                )
            } else if Self.headInputProbeIsEnabled == false,
                      content.entities.contains(where: { $0 === headInputProbe }) {
                content.remove(headInputProbe)
            }
#endif
        } else {
            if content.entities.contains(where: { $0 === panoramaInteractionSurface }) {
                content.remove(panoramaInteractionSurface)
                appModel.recordSurfaceInputProbe("shellDetached")
            }
#if DEBUG
            if content.entities.contains(where: { $0 === headInputProbe }) {
                content.remove(headInputProbe)
            }
#endif
        }
    }

    @MainActor
    private func updateWorld(in content: RealityViewContent) {
        guard needsWorld else {
            if let entity = world.entity { content.remove(entity) }
            if let anchor = world.playbackSurfaceAnchor { content.remove(anchor) }
            world.entity = nil
            world.playbackSurfaceAnchor = nil
            world.appliedEnvironment = nil
            world.appliedEnvironmentEffect = nil
            world.hasFailed = false
            appModel.clearEnvironmentSceneEffectObservation()
            return
        }

        if let entity = world.entity {
            applyRequestedEnvironmentAppearance(to: entity)
            if content.entities.contains(where: { $0 === entity }) == false {
                content.add(entity)
            }
            if let anchor = world.playbackSurfaceAnchor,
               content.entities.contains(where: { $0 === anchor }) == false {
                content.add(anchor)
            }
            recordSkyboxActivity(in: entity)
        }
    }

    @MainActor
    private func presentVideo(
        in content: RealityViewContent,
        with renderer: AVSampleBufferVideoRenderer,
        as presentation: PlaybackPresentation,
        dockedPlacement: PlaybackSurfaceTransform,
        spatialPresentationOpacity: Double
    ) {
        displayLinkProbe.recordRealityViewUpdate(
            technicalSessionID: playbackRuntime.activeTechnicalSessionID,
            renderer: renderer,
            videoComponentRevision: playbackRuntime.videoComponentRevision,
            entity: videoEntity,
            entityIsInRealityView: content.entities.contains { $0 === videoEntity },
            emit: { appModel.recordSurfaceInputProbe($0) }
        )
        let videoComponentRevision = playbackRuntime.videoComponentRevision
        guard PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
            for: presentation,
            settledPresentation: appModel.playbackPresentation,
            previousPresentation: appModel.presentationTransition?.previousPresentation,
            targetPresentation: appModel.presentationTransition?.targetPresentation,
            sourceRendererMayRelease: appModel.presentationSourceRendererMayRelease,
            targetRendererMayBind: appModel.presentationTargetRendererMayBind
        ) else {
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                "waitingForSourceRendererRelease"
            )
            logSpatialSurfaceReadiness(reason: "waitingForSourceRendererRelease")
            return
        }
        if let rendererConsumerPresentation = playbackRuntime.rendererConsumerPresentation,
           rendererConsumerPresentation.usesMainWindow {
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                "waitingForSourceRendererOwnershipToClear"
            )
            logSpatialSurfaceReadiness(reason: "waitingForSourceRendererOwnershipToClear")
            return
        }
        if playbackVideoEntityStore.hasApplied(
            videoComponentRevision: videoComponentRevision,
            to: renderer,
            presentation: presentation
        ) == false {
            surfaceActivation.cancel()
            rendererTargetObservation.cancel()
            presentationObservation.prepareForReplacementEntity()
        }
        _ = playbackVideoEntityStore.entity(
            for: renderer,
            presentation: presentation,
            videoComponentRevision: videoComponentRevision
        )
        if appModel.presentationTransition == nil,
           let departingEntity = playbackVideoEntityStore.departingEntity,
           departingEntity !== videoEntity {
            content.remove(departingEntity)
            playbackVideoEntityStore.releaseDepartingEntity()
            appModel.recordSurfaceInputProbe(
                "rendererOwnership.departingReleased scope=immersive"
                    + " presentation=\(presentation.rawValue)"
            ,
                retention: .evidence
            )
        }
        let entity = videoEntity
        let entityIsInCurrentHost = content.entities.contains { root in
            PlaybackRealityViewTopologyWritePolicy.entity(entity, isHostedUnder: root)
        }
        let topologyWriteDecision = PlaybackRealityViewTopologyWritePolicy.decision(
            currentHostIsActive: realityViewHostMarker.isActive,
            entityIsActive: entity.isActive,
            entityIsInCurrentHost: entityIsInCurrentHost
        )
        guard topologyWriteDecision == .allowed else {
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                "topologyWriteDenied"
            )
            appModel.recordSurfaceInputProbe(
                "spatialVideoTopology skipped"
                    + " reason=\(topologyWriteDecision)"
                    + " host=\(realityViewHostIdentity)"
                    + " hostActive=\(realityViewHostMarker.isActive)"
                    + " entity=\(ObjectIdentifier(entity))"
                    + " entityActive=\(entity.isActive)"
                    + " entityInCurrentHost=\(entityIsInCurrentHost)"
                    + " attachedHost=\(playbackRuntime.attachedRealityViewID ?? "none")"
            )
            return
        }
        let desiredName = "EnchronVideo.\(presentation)"
        if entity.name != desiredName {
            entity.name = desiredName
        }
        PlaybackRealityPresenter.setOpacity(
            of: entity,
            to: Float(spatialPresentationOpacity),
            animated: entity.components[OpacityComponent.self] != nil
        )
        surfaceActivation.observe(entity, in: content) {
            if videoEntity.isActive,
               videoEntity.components[VideoPlayerComponent.self] == nil {
                surfaceRefreshTick &+= 1
            }
            attachSpatialSurfaceIfReady()
        }
        let dockedAnchor: Entity?
        if presentation == .docked {
            guard let anchor = world.playbackSurfaceAnchor else { return }
            dockedAnchor = anchor
        } else {
            dockedAnchor = nil
        }

        do {
            try playbackRuntime.claimRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation)
            )
        } catch PlaybackRuntime.RuntimeError.rendererConsumerBusy {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererConsumerBusy")
            logSpatialSurfaceReadiness(reason: "rendererConsumerBusy")
            return
        } catch PlaybackRuntime.RuntimeError.rendererTransferPending {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererTransferPending")
            logSpatialSurfaceReadiness(reason: "rendererTransferPending")
            return
        } catch {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererConsumerFailed")
            playbackRuntime.setUserVisibleIssue(.surfaceAttachmentFailed)
            logger.error(
                "renderer consumer claim failed error=\(error.localizedDescription, privacy: .public)"
            )
            logSpatialSurfaceReadiness(reason: "rendererConsumerFailed")
            return
        }
        appModel.recordSpatialPlaybackSurfacePreparationStage("rendererConsumerClaimed")
        rendererTargetObservation.observe(
            entity,
            videoComponentRevision: videoComponentRevision,
            in: content,
            onEvent: { event in
                recordDisplayLinkProbe(
                    event: event,
                    entityIsInRealityView: content.entities.contains { $0 === entity }
                )
            }
        ) {
            attachSpatialSurfaceIfReady()
        }
        presentationObservation.observe(
            entity,
            in: content,
            contentTypeSessionID: realityKitContentTypeScope?.technicalSessionID,
            onChange: { change in
                if change == .videoSize {
                    updateDockedInteractionSurface(on: entity, in: content)
                }
                recordSpatialPresentationState()
            },
            onContentTypeDidChange: { contentType, eventSessionID in
                playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(
                    realityKitContentTypeScope
                )
                playbackVideoEntityStore.recordRealityKitContentType(
                    contentType,
                    forTechnicalSessionID: eventSessionID
                )
            }
        )
        surfaceAccessibilityActivation.observe(
            in: content,
            accepts: { candidate in
                PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                    candidate,
                    for: presentation
                )
            },
            onActivate: {
                toggleControlsFromSpatialSurface(.accessibilityActivate)
            }
        )
        if let dockedAnchor {
            positionDockedVideo(
                entity,
                relativeTo: dockedAnchor,
                transform: dockedPlacement
            )
        } else {
            var topologyWrites: [String] = []
            let isPanoramaRoot = content.entities.contains { $0 === entity }
            if isPanoramaRoot == false {
                entity.removeFromParent()
                topologyWrites.append("removeFromParent")
            }
            if entity.position != .zero {
                entity.position = .zero
                topologyWrites.append("position")
            }
            if entity.orientation != .init() {
                entity.orientation = .init()
                topologyWrites.append("orientation")
            }
            if entity.scale != .one {
                entity.scale = .one
                topologyWrites.append("scale")
            }
            if isPanoramaRoot == false {
                content.add(entity)
                topologyWrites.append("contentAdd")
            }
            recordDisplayLinkProbe(
                event: topologyWrites.isEmpty ? "topologyChecked" : "topologyReconciled",
                entityIsInRealityView: content.entities.contains { $0 === entity }
            )
            if topologyWrites.isEmpty == false {
                let component = entity.components[VideoPlayerComponent.self]
                let topologyWriteID = UUID()
                appModel.recordSurfaceInputProbe(
                    "spatialVideoTopology reconciled"
                        + " writeID=\(topologyWriteID.uuidString)"
                        + " presentation=\(presentation.rawValue)"
                        + " host=\(realityViewHostIdentity)"
                        + " hostActive=\(realityViewHostMarker.isActive)"
                        + " entity=\(ObjectIdentifier(entity))"
                        + " entityActiveAfterWrite=\(entity.isActive)"
                        + " componentBound=\(component?.videoRenderer === renderer)"
                        + " componentRevision=\(videoComponentRevision)"
                        + " technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")"
                        + " writes=\(topologyWrites.joined(separator: ","))",
                    retention: .evidence
                )
                verifyActiveAncestorChain(
                    after: topologyWriteID,
                    for: entity,
                    host: realityViewHostIdentity
                )
            }
        }
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: presentation,
            requestsSpatialVideoMode: playbackRuntime.requestsSpatialVideoMode
        )
        if presentation == .docked {
            updateDockedInteractionSurface(on: entity, in: content)
        } else {
            dockedInteractionSurface.removeFromParent()
#if DEBUG
            removeDockedHitTestProbes()
#endif
        }
        recordDisplayLinkProbe(
            event: "componentConfigured",
            entityIsInRealityView: content.entities.contains { $0 === entity }
        )
        appModel.recordSpatialPlaybackSurfacePreparationStage("componentConfigured")
        subtitleFollower.dockTransformProvider = { [controlsAttachmentController] in
            controlsAttachmentController.lockedControlsTransform
        }
        subtitleFollower.setActive(presentation == .panorama, in: content)
        subtitleSurface.update(
            on: subtitleParent(for: presentation),
            presentation: presentation,
            screenSize: entity.components[VideoPlayerComponent.self]?.playerScreenSize ?? .zero,
            reservedBottomFraction: 0,
            frame: playbackRuntime.activeSubtitleFrame,
            emitEnablementWrite: { appModel.recordSurfaceInputProbe($0) }
        )
        attachSpatialSurfaceIfReady()
    }

    private func subtitleParent(for presentation: PlaybackPresentation) -> Entity {
        presentation == .panorama ? subtitleFollower.root : videoEntity
    }

    @MainActor
    private func refreshSubtitleSurface() {
        let presentation = requestedPresentation
        guard presentation.usesImmersiveSpace,
              playbackRuntime.rendererConsumerPresentation == presentation else {
            return
        }
        subtitleSurface.update(
            on: subtitleParent(for: presentation),
            presentation: presentation,
            screenSize: videoEntity.components[VideoPlayerComponent.self]?.playerScreenSize ?? .zero,
            reservedBottomFraction: 0,
            frame: playbackRuntime.activeSubtitleFrame,
            emitEnablementWrite: { appModel.recordSurfaceInputProbe($0) }
        )
    }

    @MainActor
    private func attachSpatialSurfaceIfReady() {
        let presentation = requestedPresentation
        let renderer = playbackRuntime.renderer
        let componentIsBound = renderer.map {
            PlaybackRealityPresenter.isBound(
                videoEntity,
                to: $0,
                presentation: presentation
            )
        } ?? false
        logSpatialSurfaceReadiness(reason: "attachCheck")
        guard presentation.usesImmersiveSpace else { return }
        let owningPresentation =
            appModel.presentationTransition?.targetPresentation
                ?? appModel.playbackPresentation
        guard owningPresentation == presentation else { return }
        guard videoEntity.isActive else {
            let parent = videoEntity.parent
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                [
                    "entityInactive",
                    "entityEnabled=\(videoEntity.isEnabled)",
                    "parent=\(parent?.name ?? "none")",
                    "parentEnabled=\(parent?.isEnabled.description ?? "none")",
                    "parentActive=\(parent?.isActive.description ?? "none")",
                    "worldEnabled=\(world.entity?.isEnabled.description ?? "none")",
                    "worldActive=\(world.entity?.isActive.description ?? "none")"
                ].joined(separator: ",")
            )
            return
        }
        guard renderer != nil else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererUnavailable")
            return
        }
        guard componentIsBound else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForComponentBinding")
            return
        }
        guard rendererTargetObservation.targetIsAvailable else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForRendererTarget")
            return
        }
        guard playbackRuntime.rendererConsumerEntityID
                == entityID(for: presentation) else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForConsumerClaim")
            return
        }
        appModel.recordSpatialPlaybackSurfacePreparationStage("attachingSurface")
        playbackRuntime.videoRendererTargetDidBind(
            revision: playbackRuntime.videoComponentRevision,
            entityID: entityID(for: presentation)
        )
        if let component = videoEntity.components[VideoPlayerComponent.self] {
            let recoveryAction = presentationObservation.modeRecoveryAction(
                to: videoEntity,
                presentation: presentation,
                component: component,
                projection: playbackRuntime.effectiveProjectionType,
                sourceContentKind: playbackRuntime.sourceVideoContentKind,
                provenance: playbackRuntime.activeMediaFormatProvenance,
                observedContentType:
                    playbackVideoEntityStore.realityKitContentType
            )
            switch recoveryAction {
            case .none:
                break
            case .requestModesAgain:
                appModel.recordSurfaceInputProbe(
                    "modeRequestRetry presentation=\(presentation)"
                )
                PlaybackRealityPresenter.reapplyDesiredModesAfterSceneActivation(
                    videoEntity,
                    presentation: presentation,
                    requestsSpatialVideoMode: playbackRuntime.requestsSpatialVideoMode
                )
            }
        }
        do {
            try playbackRuntime.attach(
                entityID: entityID(for: presentation),
                realityViewID: realityViewID(for: presentation),
                presentation: presentation
            )
            appModel.recordSpatialPlaybackSurfacePreparationStage("surfaceAttached")
            recordSpatialPresentationState()
        } catch {
            appModel.recordSpatialPlaybackSurfacePreparationStage("surfaceAttachFailed")
            playbackRuntime.setUserVisibleIssue(.surfaceAttachmentFailed)
            logger.error(
                "spatial surface attach failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func logSpatialSurfaceReadiness(reason: String) {
        let presentation = requestedPresentation
        let renderer = playbackRuntime.renderer
        let component = videoEntity.components[VideoPlayerComponent.self]
        let componentIsBound = renderer.map {
            component?.videoRenderer === $0
        } ?? false
        let signature = [
            presentation.rawValue,
            String(describing: ObjectIdentifier(videoEntity)),
            videoEntity.isActive ? "active" : "inactive",
            renderer == nil ? "rendererMissing" : "rendererAvailable",
            componentIsBound ? "componentBound" : "componentUnbound",
            rendererTargetObservation.targetIsAvailable
                ? "targetAvailable"
                : "targetUnavailable",
            playbackRuntime.rendererConsumerEntityID == entityID(for: presentation)
                ? "consumerClaimed"
                : "consumerUnclaimed",
            playbackRuntime.attachedPresentation == presentation
                ? "runtimeAttached"
                : "runtimeDetached",
            "componentRevision=\(playbackRuntime.videoComponentRevision)",
            "boundRevision=\(playbackRuntime.boundVideoComponentRevision.map(String.init) ?? "none")",
            "contentType=\(playbackVideoEntityStore.realityKitContentType)",
            "desiredImmersiveMode=\(String(describing: component?.desiredImmersiveViewingMode))",
            "actualImmersiveMode=\(String(describing: component?.immersiveViewingMode))",
            "desiredViewingMode=\(String(describing: component?.desiredViewingMode))",
            "actualViewingMode=\(String(describing: component?.viewingMode))",
            "rendering=\(String(describing: component?.currentRenderingStatus))"
        ].joined(separator: "|")
        guard presentationObservation.shouldLogSurfaceReadiness(
            reason: reason,
            signature: signature
        ) else { return }
        logger.notice(
            "spatial surface facts \(reason, privacy: .public)|\(signature, privacy: .public)"
        )
    }

    @MainActor
    private func recordSpatialPresentationState() {
        let presentation = requestedPresentation
        let realityViewID = realityViewID(for: presentation)
        guard presentation.usesImmersiveSpace,
              videoEntity.isActive,
              rendererTargetObservation.targetIsAvailable,
              playbackRuntime.rendererConsumerEntityID
                == entityID(for: presentation),
              playbackRuntime.attachedPresentation == presentation,
              let renderer = playbackRuntime.renderer,
              PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: presentation
              ),
              let component = videoEntity.components[VideoPlayerComponent.self] else {
            return
        }
        let parentID = videoEntity.parent.map { String(describing: ObjectIdentifier($0)) }
        let immersiveModeIsSettled = presentation != .panorama
            || SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: playbackRuntime.effectiveContentIsPanoramic,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: String(
                    describing: component.desiredImmersiveViewingMode
                ),
                observedImmersiveViewingMode: component.immersiveViewingMode.map {
                    String(describing: $0)
                }
            )
        let contentTypeMatchesProjection = presentation != .panorama
            || SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: playbackRuntime.effectiveProjectionType,
                sourceContentKind: playbackRuntime.sourceVideoContentKind,
                provenance: playbackRuntime.activeMediaFormatProvenance,
                observedContentType: playbackVideoEntityStore.realityKitContentType
            )
        let diagnostics = playbackRuntime.diagnostics
        let debugSnapshot = playbackRuntime.debugSnapshot()
        let rendererState = debugSnapshot?.rendererState
        let audioRendererState = debugSnapshot?.audioRendererState
        let timelineControlState = debugSnapshot?.timelineControlState
        let timelineRateActivation = timelineControlState?.lastRateActivation
        let timelineStop = timelineControlState?.lastStop
        let displayedPixelBuffer = renderer.displayedPixelBuffer() != nil
        recordDisplayLinkProbe(event: "presentationState", entityIsInRealityView: nil)
        let displayedFrameObservationCount = (
            rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let surfaceOpacity = videoEntity.components[OpacityComponent.self]?.opacity ?? 1
        let viewingModeMatches =
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                observedViewingMode: component.viewingMode.map {
                    String(describing: $0)
                },
                requiresObservedMode: presentation == .panorama
            )
        let explicitOverrideAdoptionIsConfirmed = presentation == .panorama
            && SpatialPlaybackSurfaceSettlementPolicy
                .explicitOverrideAdoptionIsConfirmed(
                    projection: playbackRuntime.effectiveProjectionType,
                    stereoLayout: playbackRuntime.effectiveStereoLayout,
                    provenance: playbackRuntime.activeMediaFormatProvenance,
                    acceptedRendererProjectionKind:
                        playbackRuntime.acceptedRendererProjectionKind,
                    desiredImmersiveViewingMode: String(
                        describing: component.desiredImmersiveViewingMode
                    ),
                    observedImmersiveViewingMode:
                        component.immersiveViewingMode.map {
                            String(describing: $0)
                        },
                    observedViewingMode: component.viewingMode.map {
                        String(describing: $0)
                    }
                )
        let readiness = SpatialPresentationReadiness(
            componentIsReady: component.currentRenderingStatus == .ready,
            immersiveModeMatches: immersiveModeIsSettled,
            projectionIsAdopted: contentTypeMatchesProjection
                || explicitOverrideAdoptionIsConfirmed,
            viewingModeMatches: viewingModeMatches,
            spatialModeMatches:
                component.spatialVideoMode == component.desiredSpatialVideoMode,
            displayedPixelBuffer: displayedPixelBuffer
        )
        if let target = portalToPanoramaRevealTarget,
           targetRevealState.admit(target, when: readiness) {
            appModel.recordSurfaceInputProbe(
                "panoramaPixelProofReveal"
                    + " transition=\(target.transitionID)"
                    + " technicalSession=\(target.technicalSessionID)"
                    + " componentRevision=\(target.videoComponentRevision)"
                    + " entity=\(target.entityID)"
            )
            surfaceRefreshTick &+= 1
        }
        let isSettled = readiness.isSettled
        let settlementFields = [
            "settled=\(isSettled)",
            "ready=\(readiness.componentIsReady)",
            "immersiveMode=\(readiness.immersiveModeMatches)",
            "contentTypeMatches=\(contentTypeMatchesProjection)",
            "overrideAdopted=\(explicitOverrideAdoptionIsConfirmed)",
            "viewingMode=\(readiness.viewingModeMatches)",
            "spatialMode=\(readiness.spatialModeMatches)",
            "pixels=\(readiness.displayedPixelBuffer)",
            "requiresFlushToResumeDecoding=\(renderer.requiresFlushToResumeDecoding)",
            "isReadyForMoreMediaData=\(renderer.isReadyForMoreMediaData)",
            "rendererStatus=\(String(describing: renderer.status))",
            "rendererError=\(renderer.error?.localizedDescription ?? "none")",
            "diagnosticRendererStatus=\(diagnostics.rendererStatus)",
            "diagnosticRendererError=\(diagnostics.rendererError)",
            "enqueuedSampleCount=\(diagnostics.enqueuedSampleCount)",
            "displayedFrameObservationCount=\(displayedFrameObservationCount)",
            "flushCount=\(rendererState.map { String($0.flushCount) } ?? "none")",
            "timelineConfigured=\(rendererState.map { String($0.timelineConfigured) } ?? "none")",
            "synchronizerTime=\(rendererState.map { String($0.currentTimeSeconds) } ?? "none")",
            "synchronizerRate=\(rendererState.map { String($0.rate) } ?? "none")",
            "actualTimebaseRate=\(rendererState?.actualTimebaseRate.map { String($0) } ?? "none")",
            "effectiveTimebaseRate=\(rendererState?.effectiveTimebaseRate.map { String($0) } ?? "none")",
            "timebaseSourceType=\(rendererState?.timebaseSourceType ?? "none")",
            "timebaseSourceTime=\(rendererState?.timebaseSourceTimeSeconds.map { String($0) } ?? "none")",
            "timebaseUltimateSourceTime=\(rendererState?.timebaseUltimateSourceTimeSeconds.map { String($0) } ?? "none")",
            "streamEpoch=\(rendererState.map { String($0.streamEpoch) } ?? "none")",
            "lastVideoPTS=\(debugSnapshot?.lastVideoSample.map { String($0.presentationTimeSeconds) } ?? "none")",
            "lastVideoDTS=\(debugSnapshot?.lastVideoSample?.decodeTimeSeconds.map { String($0) } ?? "none")",
            "decoderBootstrapComplete=\(debugSnapshot?.decoderBootstrap.map { String($0.complete) } ?? "none")",
            "acceptedRendererInputCount=\(debugSnapshot.map { String($0.acceptedRendererInputCount) } ?? "none")",
            "backpressureCount=\(debugSnapshot.map { String($0.backpressureCount) } ?? "none")",
            "lastAudioPTS=\(debugSnapshot?.lastAudioSample.map { String($0.presentationTimeSeconds) } ?? "none")",
            "audioSampleBufferCount=\(debugSnapshot.map { String($0.audioSampleBufferCount) } ?? "none")",
            "audioRendererEnqueuedSampleBufferCount=\(audioRendererState.map { String($0.enqueuedSampleBufferCount) } ?? "none")",
            "audioRendererStatus=\(audioRendererState?.status ?? "none")",
            "audioRendererError=\(audioRendererState?.error ?? "none")",
            "audioRendererReadyForMoreMediaData=\(audioRendererState.map { String($0.isReadyForMoreMediaData) } ?? "none")",
            "audioRendererHasSufficientMediaData=\(audioRendererState.map { String($0.hasSufficientMediaDataForReliablePlaybackStart) } ?? "none")",
            "timelineRecovery=\(debugSnapshot?.timelineProgressRecovery?.outcome.rawValue ?? "none")",
            "timelineRecoveryIncident=\(debugSnapshot?.timelineProgressRecovery.map { String($0.incidentID) } ?? "none")",
            "timelineRecoverySource=\(debugSnapshot?.timelineProgressRecovery?.detectionSource?.rawValue ?? "none")",
            "timelineRecoveryLanes=\(debugSnapshot?.timelineProgressRecovery?.detectingLanes.joined(separator: "+") ?? "none")",
            "timelineRecoveryWatchdogCause=\(debugSnapshot?.timelineProgressRecovery?.watchdogCause?.rawValue ?? "none")",
            "timelineRecoveryWatchdogCount=\(debugSnapshot?.timelineProgressRecovery?.watchdogConsecutiveObservationCount.map(String.init) ?? "none")",
            "timelineRecoveryFrozenMediaTime=\(debugSnapshot?.timelineProgressRecovery.map { String($0.frozenMediaTimeSeconds) } ?? "none")",
            "timelineRecoveryReanchorHostTime=\(debugSnapshot?.timelineProgressRecovery?.reanchorHostTimeSeconds.map { String($0) } ?? "none")",
            "timelineRecoveryPostMediaTime=\(debugSnapshot?.timelineProgressRecovery?.postRecoveryMediaTimeSeconds.map { String($0) } ?? "none")",
            "timelineRecoveryAttemptCount=\(debugSnapshot?.timelineProgressRecovery.map { String($0.attemptCount) } ?? "none")",
            "isPrerolling=\(timelineControlState.map { String($0.isPrerolling) } ?? "none")",
            "hasStartedTimeline=\(timelineControlState.map { String($0.hasStartedTimeline) } ?? "none")",
            "timelineStartRate=\(timelineControlState.map { String($0.timelineStartRate) } ?? "none")",
            "requestedTimelineStart=\(timelineControlState?.requestedTimelineStartSeconds.map { String($0) } ?? "none")",
            "timelineActivationReason=\(timelineRateActivation?.reason.rawValue ?? "none")",
            "timelineActivationMediaTime=\(timelineRateActivation?.mediaTimeSeconds.map { String($0) } ?? "none")",
            "timelineActivationHostTime=\(timelineRateActivation?.hostTimeSeconds.map { String($0) } ?? "none")",
            "timelineActivationSequence=\(timelineRateActivation.map { String($0.sequence) } ?? "none")",
            "timelineActivationReturned=\(timelineRateActivation.map { String($0.synchronousApplicationReturned) } ?? "none")",
            "timelineActivationCurrentGeneration=\(timelineRateActivation.map { String($0.currentVideoDeliveryGeneration) } ?? "none")",
            "timelineActivationCapturedGeneration=\(timelineRateActivation?.capturedVideoDeliveryGeneration.map { String($0) } ?? "none")",
            "timelineStopReason=\(timelineStop?.reason.rawValue ?? "none")",
            "timelineStopMediaTime=\(timelineStop?.mediaTimeSeconds.map { String($0) } ?? "none")",
            "timelineStopSequence=\(timelineStop.map { String($0.sequence) } ?? "none")",
            "timelineStopCurrentGeneration=\(timelineStop.map { String($0.currentVideoDeliveryGeneration) } ?? "none")",
            "timelineStopCapturedGeneration=\(timelineStop?.capturedVideoDeliveryGeneration.map { String($0) } ?? "none")",
            "surfaceOpacity=\(surfaceOpacity)",
            "targetOpacity=\(spatialPresentationOpacity)",
            "visualCutover=\(appModel.presentationVisualCutoverMayBegin)",
            "rkContentType=\(playbackVideoEntityStore.realityKitContentType)",
            "provenance=\(playbackRuntime.activeMediaFormatProvenance.rawValue)",
            "acceptedProjection=\(String(describing: playbackRuntime.acceptedRendererProjectionKind))",
            "status=\(String(describing: component.currentRenderingStatus))",
            "wantImmersive=\(String(describing: component.desiredImmersiveViewingMode))",
            "gotImmersive=\(component.immersiveViewingMode.map { String(describing: $0) } ?? "none")",
            "wantViewing=\(String(describing: component.desiredViewingMode))",
            "gotViewing=\(component.viewingMode.map { String(describing: $0) } ?? "none")",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "componentBound=\(playbackRuntime.renderer.map { component.videoRenderer === $0 } ?? false)",
            "technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")",
            "retiring=\(playbackRuntime.retiringTechnicalSessionCount)"
        ]
        let settlementBreakdown = settlementFields.joined(separator: ",")
        let settlementSignature = PlaybackSettlementProbeSignature.make(
            fields: settlementFields
        )
        if presentationObservation.shouldLogSurfaceReadiness(
            reason: "settlement",
            signature: settlementSignature,
            heartbeat: 2
        ) {
            appModel.recordSurfaceInputProbe("settlement \(settlementBreakdown)")
        }
        recordSpatialPlaybackSurfaceObservation(
            presentation: presentation,
            component: component,
            settled: isSettled
        )
        playbackRuntime.recordPresentationState(
            presentation: presentation,
            phase: isSettled ? .settled : .surfaceAttached,
            entityID: entityID(for: presentation),
            technicalSessionID: playbackRuntime.activeTechnicalSessionID,
            videoComponentRevision: playbackRuntime.videoComponentRevision,
            streamEpoch: debugSnapshot?.streamEpoch,
            realityViewID: realityViewID,
            entityParentID: parentID,
            desiredImmersiveViewingMode: String(describing: component.desiredImmersiveViewingMode),
            actualImmersiveViewingMode: component.immersiveViewingMode.map { String(describing: $0) },
            desiredViewingMode: String(describing: component.desiredViewingMode),
            actualViewingMode: component.viewingMode.map { String(describing: $0) },
            desiredSpatialVideoMode: String(describing: component.desiredSpatialVideoMode),
            actualSpatialVideoMode: String(describing: component.spatialVideoMode),
            componentRenderingStatus: String(describing: component.currentRenderingStatus),
            displayedPixelBuffer: displayedPixelBuffer
        )
    }

    @MainActor
    private func recordSpatialPlaybackSurfaceObservation(
        presentation: PlaybackPresentation,
        component: VideoPlayerComponent,
        settled: Bool
    ) {
        let worldPosition = videoEntity.position(relativeTo: nil)
        let worldOrientation = videoEntity.orientation(relativeTo: nil)
        let worldScale = videoEntity.scale(relativeTo: nil)
        let worldDistance = simd_length(worldPosition)
        let worldElevationDegrees: Float
        let forwardToUserDot: Float
        if worldDistance > 0.0001 {
            worldElevationDegrees = asin(
                min(max(worldPosition.y / worldDistance, -1), 1)
            ) * 180 / .pi
            let entityForward = simd_normalize(
                worldOrientation.act(SIMD3<Float>(0, 0, -1))
            )
            forwardToUserDot = simd_dot(
                entityForward,
                simd_normalize(-worldPosition)
            )
        } else {
            worldElevationDegrees = 0
            forwardToUserDot = 0
        }
        let playerScreenSize = component.playerScreenSize
        appModel.recordSpatialPlaybackSurfaceObservation(
            SpatialPlaybackSurfaceObservation(
                presentation: presentation.rawValue,
                parentName: videoEntity.parent?.name ?? "none",
                anchorMatched: presentation != .docked
                    || videoEntity.parent === world.playbackSurfaceAnchor,
                localPosition: videoEntity.position,
                worldPosition: worldPosition,
                localScale: videoEntity.scale,
                worldScale: worldScale,
                worldDistance: worldDistance,
                worldElevationDegrees: worldElevationDegrees,
                forwardToUserDot: forwardToUserDot,
                playerScreenSize: playerScreenSize,
                renderedSize: SIMD2<Float>(
                    playerScreenSize.x * videoEntity.scale.x,
                    playerScreenSize.y * videoEntity.scale.y
                ),
                renderingReady: component.currentRenderingStatus == .ready,
                surfaceOpacity: videoEntity.components[OpacityComponent.self]?.opacity ?? 1,
                contentType: playbackVideoEntityStore.realityKitContentType,
                desiredImmersiveViewingMode: String(
                    describing: component.desiredImmersiveViewingMode
                ),
                actualImmersiveViewingMode: component.immersiveViewingMode.map {
                    String(describing: $0)
                } ?? "none",
                desiredViewingMode: String(describing: component.desiredViewingMode),
                actualViewingMode: component.viewingMode.map {
                    String(describing: $0)
                } ?? "none",
                desiredSpatialVideoMode: String(
                    describing: component.desiredSpatialVideoMode
                ),
                actualSpatialVideoMode: String(describing: component.spatialVideoMode),
                settled: settled
            )
        )
    }

    @MainActor
    private func loadWorld(
        into content: RealityViewContent,
        dockedPlacement: PlaybackSurfaceTransform,
        spatialPresentationOpacity: Double
    ) async {
        guard world.entity == nil, world.isLoading == false, world.hasFailed == false else { return }
        world.isLoading = true
        appModel.recordSpatialPlaybackSurfacePreparationStage("loadingWorld")
        defer { world.isLoading = false }
        logger.notice("world load started")
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "worldLoad event=started"
                + " resource=\(EnvironmentSceneMapping.worldSceneName)"
                + " bundle=RealityKitContent"
        )
#endif
        do {
            let entity = try await Entity(
                named: EnvironmentSceneMapping.worldSceneName,
                in: realityKitContentBundle
            )
            try Task.checkCancellation()
            let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: entity)
            let anchorWorldTransform = anchor.transformMatrix(relativeTo: nil)
            guard applyRequestedEnvironmentAppearance(to: entity) else {
                throw EnvironmentSceneEffectError.skyboxMissing
            }
            anchor.removeFromParent()
            content.add(entity)
            content.add(anchor)
            anchor.setTransformMatrix(anchorWorldTransform, relativeTo: nil)
            world.entity = entity
            world.playbackSurfaceAnchor = anchor
            appModel.recordSpatialPlaybackSurfacePreparationStage("worldReady")
            recordSkyboxActivity(in: entity)
            logger.notice("world load completed")
#if DEBUG
            appModel.recordSurfaceInputProbe(
                "worldLoad event=completed"
                    + " anchor=\(PlaybackSurfaceAnchorResolver.canonicalName)",
                retention: .evidence
            )
#endif
            update(
                content,
                revision: surfaceRefreshTick,
                dockedPlacement: dockedPlacement,
                spatialPresentationOpacity: spatialPresentationOpacity
            )
        } catch is CancellationError {
            logger.notice("world load cancelled")
#if DEBUG
            appModel.recordSurfaceInputProbe("worldLoad event=cancelled")
#endif
        } catch {
            world.hasFailed = true
            appModel.recordSpatialPlaybackSurfacePreparationStage("worldLoadFailed")
            logger.error("world load failed error=\(error.localizedDescription, privacy: .public)")
#if DEBUG
            appModel.recordSurfaceInputProbe(
                "worldLoad event=failed"
                    + " errorType=\(String(reflecting: type(of: error)))"
                    + " error=\(error.localizedDescription)"
            )
#endif
            playbackRuntime.setUserVisibleIssue(.environmentLoadingFailed)
        }
    }

    @MainActor
    @discardableResult
    private func applyRequestedEnvironmentAppearance(to entity: Entity) -> Bool {
        guard let environment = requestedEnvironmentContext.environment else {
            EnvironmentSceneAppearanceApplier.clear(
                in: entity,
                emitEnablementWrite: { appModel.recordSurfaceInputProbe($0) }
            )
            world.appliedEnvironment = nil
            world.appliedEnvironmentEffect = nil
            appModel.clearEnvironmentSceneEffectObservation()
            return true
        }
        let effect = requestedEnvironmentContext.effect
        if world.appliedEnvironment == environment,
           world.appliedEnvironmentEffect == effect,
           appModel.environmentSkyboxOpacity != nil {
            return true
        }
        guard let opacity = EnvironmentSceneAppearanceApplier.apply(
            environment: environment,
            effect: effect,
            to: entity,
            emitEnablementWrite: { appModel.recordSurfaceInputProbe($0) }
        ) else {
            return false
        }
        world.appliedEnvironment = environment
        world.appliedEnvironmentEffect = effect
        appModel.recordEnvironmentSceneEffect(opacity: opacity)
        return true
    }

    @MainActor
    private func recordSkyboxActivity(in entity: Entity) {
        appModel.recordEnvironmentSkyboxIsActive(
            entity.findEntity(named: EnvironmentSceneAppearanceApplier.skyboxName)?.isActive == true
                || entity.findEntity(
                    named: EnvironmentSceneAppearanceApplier.scenicPlaceholderName
                )?.isActive == true
        )
    }

    @MainActor
    private func removeVideo(from content: RealityViewContent, reason: String) {
        let consumerPresentation = playbackRuntime.rendererConsumerPresentation
        let attachedPresentation = playbackRuntime.attachedPresentation
        let ownsSpatialConsumer = consumerPresentation?.usesImmersiveSpace == true
        let ownsSpatialAttachment = attachedPresentation?.usesImmersiveSpace == true
        guard ownsSpatialConsumer || ownsSpatialAttachment else { return }

        logger.notice("video surface removed reason=\(reason, privacy: .public)")
        if preservesDepartingSpatialSurfaceForFade {
            releaseSpatialRendererOwnershipWhileKeepingVisibleSurface()
            return
        }
        if let consumerPresentation,
           consumerPresentation.usesImmersiveSpace,
           playbackRuntime.rendererConsumerEntityID == entityID(for: consumerPresentation) {
            content.remove(videoEntity)
        }
        releaseSpatialSurface()
    }

    @MainActor
    private func releaseSpatialSurface() {
        let presentation = playbackRuntime.rendererConsumerPresentation
            ?? playbackRuntime.attachedPresentation
        subtitleSurface.remove {
            appModel.recordSurfaceInputProbe($0)
        }
        surfaceActivation.cancel()
        surfaceAccessibilityActivation.cancel()
        rendererTargetObservation.cancel()
        presentationObservation.cancel()
        displayLinkProbe.reset()
        appModel.clearSpatialPlaybackSurfaceObservation()
        panoramaInteractionSurface.removeFromParent()
        subtitleFollower.stop()
#if DEBUG
        headInputProbe.removeFromParent()
        removeDockedHitTestProbes()
#endif
        guard let presentation, presentation.usesImmersiveSpace else { return }
        videoEntity.removeFromParent()
        let preservesPlaybackComponent = playbackRuntime.activeSessionID != nil
        if preservesPlaybackComponent == false {
            playbackVideoEntityStore.releasePlaybackComponent()
        }
        if playbackRuntime.rendererConsumerEntityID == entityID(for: presentation) {
            playbackRuntime.releaseRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation),
                preservingVideoComponent: preservesPlaybackComponent
            )
        }
        detachSpatialSurface()
    }

    private var preservesDepartingSpatialSurfaceForFade: Bool {
        guard let transition = appModel.presentationTransition else {
            return false
        }
        return transition.previousPresentation.usesImmersiveSpace
            && transition.targetPresentation.usesMainWindow
            && appModel.presentationSourceRendererMayRelease
    }

    private func releaseSpatialRendererOwnershipWhileKeepingVisibleSurface() {
        let sourcePresentation = appModel.presentationTransition?
            .previousPresentation
        surfaceActivation.cancel()
        surfaceAccessibilityActivation.cancel()
        rendererTargetObservation.cancel()
        presentationObservation.cancel()
        displayLinkProbe.reset()
        subtitleSurface.remove {
            appModel.recordSurfaceInputProbe($0)
        }
        guard let sourcePresentation,
              playbackRuntime.rendererConsumerEntityID
                == entityID(for: sourcePresentation) else {
            return
        }
        playbackVideoEntityStore.releaseInteractionSurfacesForRealityViewTransfer()
        playbackRuntime.releaseRendererConsumer(
            presentation: sourcePresentation,
            entityID: entityID(for: sourcePresentation),
            preservingVideoComponent: false
        )
        playbackRuntime.detachSurface(
            entityID: entityID(for: sourcePresentation),
            realityViewID: realityViewID(for: sourcePresentation)
        )
    }

    private func verifyActiveAncestorChain(
        after topologyWriteID: UUID,
        for entity: Entity,
        host: PlaybackRealityViewHostIdentity
    ) {
        Task { @MainActor in
            for _ in 0..<PlaybackSurfaceActivation.maximumRetryCountForView {
                if entity.isActive {
                    appModel.recordSurfaceInputProbe(
                        "spatialVideoTopology ownershipVerified"
                            + " writeID=\(topologyWriteID.uuidString)"
                            + " host=\(host)"
                            + " entity=\(ObjectIdentifier(entity))"
                            + " ancestorChainActive=true",
                        retention: .evidence
                    )
                    return
                }
                try? await Task.sleep(
                    for: PlaybackSurfaceActivation.retryIntervalForView
                )
            }
            appModel.recordSurfaceInputProbe(
                "spatialVideoTopology ownershipVerified"
                    + " writeID=\(topologyWriteID.uuidString)"
                    + " host=\(host)"
                    + " entity=\(ObjectIdentifier(entity))"
                    + " ancestorChainActive=false",
                retention: .evidence
            )
        }
    }

    private func recordDisplayLinkProbe(
        event: String,
        entityIsInRealityView: Bool?,
        isExplicitFirstFrameWaitSample: Bool = false
    ) {
        guard let renderer = playbackRuntime.renderer else { return }
        displayLinkProbe.record(
            event: event,
            technicalSessionID: playbackRuntime.activeTechnicalSessionID,
            renderer: renderer,
            videoComponentRevision: playbackRuntime.videoComponentRevision,
            entity: videoEntity,
            entityIsInRealityView: entityIsInRealityView,
            targetIsAvailable: rendererTargetObservation.targetIsAvailable,
            isExplicitFirstFrameWaitSample: isExplicitFirstFrameWaitSample,
            emit: { appModel.recordSurfaceInputProbe($0) }
        )
    }

    private var spatialFirstFrameProbeKey: String {
        [
            requestedPresentation.rawValue,
            playbackRuntime.activeTechnicalSessionID ?? "sessionNone",
            String(playbackRuntime.videoComponentRevision),
            entityID(for: requestedPresentation)
        ].joined(separator: "|")
    }

    @MainActor
    private func sampleWhileWaitingForSpatialFirstFrame() async {
        guard requestedPresentation.usesImmersiveSpace else { return }
        while spatialSurfaceAttachmentCanStillSettle {
            guard Task.isCancelled == false,
                  let renderer = playbackRuntime.renderer else {
                return
            }
            recordDisplayLinkProbe(
                event: "firstFrameWaitSample",
                entityIsInRealityView: nil,
                isExplicitFirstFrameWaitSample: true
            )
            if renderer.displayedPixelBuffer() != nil {
                return
            }
            try? await Task.sleep(for: PlaybackSurfaceActivation.retryIntervalForView)
        }
    }

    private var spatialSurfaceReadinessKey: String {
        let presentation = requestedPresentation
        let rendererID = playbackRuntime.renderer.map {
            String(describing: ObjectIdentifier($0))
        } ?? "rendererNone"
        return [
            presentation.rawValue,
            realityKitContentTypeScope?.sessionID ?? "sessionNone",
            playbackRuntime.activeMediaFormatProvenance.rawValue,
            playbackRuntime.sourceVideoContentKind.rawValue,
            playbackRuntime.effectiveProjectionType.rawValue,
            String(playbackRuntime.effectiveHorizontalFieldOfViewDegrees),
            playbackRuntime.effectiveStereoLayout.rawValue,
            playbackRuntime.effectiveVideoFormatRevision.map(String.init)
                ?? "formatRevisionNone",
            rendererID,
            String(playbackRuntime.videoComponentRevision),
            playbackRuntime.rendererConsumerEntityID ?? "consumerNone",
            playbackRuntime.attachedPresentation?.rawValue ?? "attachedNone",
            playbackRuntime.hasActivePlaybackRequest ? "requestActive" : "requestNone",
            playbackRuntime.productLifecycle.rawValue,
            appModel.presentationSourceRendererMayRelease
                ? "sourceMayRelease"
                : "sourceMustRemain",
            appModel.presentationTargetRendererMayBind
                ? "targetMayBind"
                : "targetMustWait"
        ].joined(separator: "|")
    }

    @MainActor
    private func retrySpatialSurfaceAttachment() async {
        var requestedUpdateCount: UInt64 = 0
        appModel.recordSurfaceInputProbe(
            spatialFirstFrameUpdateDriveFact(
                event: "started",
                requestedUpdateCount: requestedUpdateCount
            )
        )
        while true {
            guard Task.isCancelled == false else {
                appModel.recordSurfaceInputProbe(
                    spatialFirstFrameUpdateDriveFact(
                        event: "stopped:cancelled",
                        requestedUpdateCount: requestedUpdateCount
                    )
                )
                return
            }

            let decision = SpatialFirstFrameUpdateDrivePolicy.decide(
                surfaceCanStillSettle: spatialSurfaceAttachmentCanStillSettle,
                currentRendererHasPixels:
                    playbackRuntime.renderer?.displayedPixelBuffer() != nil
            )
            switch decision {
            case .firstFrameArrived:
                appModel.recordSurfaceInputProbe(
                    spatialFirstFrameUpdateDriveFact(
                        event: "stopped:firstFrameArrived",
                        requestedUpdateCount: requestedUpdateCount
                    )
                )
                return
            case .surfaceNoLongerViable:
                appModel.recordSurfaceInputProbe(
                    spatialFirstFrameUpdateDriveFact(
                        event: "stopped:surfaceNoLongerViable",
                        requestedUpdateCount: requestedUpdateCount
                    )
                )
                return
            case .requestUpdate:
                break
            }
            surfaceRefreshTick &+= 1
            requestedUpdateCount &+= 1
            surfaceActivation.requestRetry()
            try? await Task.sleep(for: PlaybackSurfaceActivation.retryIntervalForView)
        }
    }

    private func spatialFirstFrameUpdateDriveFact(
        event: String,
        requestedUpdateCount: UInt64
    ) -> String {
        let observation = appModel.spatialPlaybackSurfaceObservation
        return "spatialFirstFrameUpdateDrive event=\(event)"
            + " requestedUpdateCount=\(requestedUpdateCount)"
            + " requestedPresentation=\(requestedPresentation.rawValue)"
            + " observationPresentation=\(observation.presentation)"
            + " observationSettled=\(observation.settled)"
            + " currentRendererPixels=\(playbackRuntime.renderer?.displayedPixelBuffer() != nil)"
            + " attachedPresentation=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")"
            + " rendererConsumer=\(playbackRuntime.rendererConsumerEntityID ?? "none")"
            + " targetEntity=\(entityID(for: requestedPresentation))"
            + " lifecycle=\(playbackRuntime.productLifecycle.rawValue)"
    }

    private var spatialSurfaceAttachmentCanStillSettle: Bool {
        guard requestedPresentation.usesImmersiveSpace,
              playbackRuntime.hasActivePlaybackRequest else {
            return false
        }
        switch playbackRuntime.productLifecycle {
        case .loading, .ready, .playing, .paused, .ended:
            return true
        case .idle, .failed:
            return false
        }
    }

    private func entityID(for presentation: PlaybackPresentation) -> String {
        playbackVideoEntityStore.hostedEntityID(
            for: presentation,
            during: appModel.presentationTransition
        )
    }

    private func realityViewID(for presentation: PlaybackPresentation) -> String {
        _ = presentation
        return realityViewHostIdentity.description
    }

    private func detachSpatialSurface() {
        guard let presentation = playbackRuntime.attachedPresentation,
              presentation.usesImmersiveSpace else { return }
        playbackRuntime.detachSurface(
            entityID: entityID(for: presentation),
            realityViewID: realityViewID(for: presentation)
        )
    }

    private func positionDockedVideo(
        _ entity: Entity,
        relativeTo anchor: Entity,
        transform: PlaybackSurfaceTransform
    ) {
        PlaybackSurfacePlacement.dock(
            entity,
            to: anchor,
            transform: transform
        )
    }

    private func updateDockedInteractionSurface(
        on entity: Entity,
        in content: RealityViewContent
    ) {
        guard requestedPresentation == .docked else {
            recordDockedInteractionSurfaceAssemblyProbe(
                "skipped reason=presentationNotDocked"
                    + " requestedPresentation=\(requestedPresentation.rawValue)"
                    + " candidate=\(ObjectIdentifier(entity))"
            )
            return
        }
        guard videoEntity === entity else {
            recordDockedInteractionSurfaceAssemblyProbe(
                "skipped reason=videoEntityMismatch"
                    + " candidate=\(ObjectIdentifier(entity))"
                    + " expected=\(ObjectIdentifier(videoEntity))"
            )
            return
        }
        guard let component = entity.components[VideoPlayerComponent.self] else {
            recordDockedInteractionSurfaceAssemblyProbe(
                "skipped reason=videoPlayerComponentMissing"
                    + " entity=\(ObjectIdentifier(entity))"
                    + " active=\(entity.isActive)"
                    + " parent=\(entity.parent?.name ?? "none")"
            )
            return
        }
        PlaybackDockedInteractionSurface.install(
            dockedInteractionSurface,
            on: entity,
            screenSize: component.playerScreenSize
        )
#if DEBUG
        if Self.dockedHitTestProbesAreEnabled {
            installDockedHitTestProbes(
                beside: entity,
                screenSize: component.playerScreenSize
            )
        } else {
            removeDockedHitTestProbes()
        }
#endif
        let collisionExtents = dockedInteractionSurface
            .components[CollisionComponent.self]?
            .shapes.first?
            .bounds.extents
        recordDockedInteractionSurfaceAssemblyProbe(
            "installed"
                + " name=\(dockedInteractionSurface.name)"
                + " entity=\(ObjectIdentifier(dockedInteractionSurface))"
                + " parent=\(dockedInteractionSurface.parent?.name ?? "none")"
                + " parentMatchesVideo=\(dockedInteractionSurface.parent === entity)"
                + " screenSize=\(component.playerScreenSize)"
                + " collisionExtents=\(collisionExtents.map(String.init(describing:)) ?? "none")"
                + " localPosition=\(dockedInteractionSurface.position)"
                + " worldPosition=\(dockedInteractionSurface.position(relativeTo: nil))"
                + " worldScale=\(dockedInteractionSurface.scale(relativeTo: nil))"
                + " active=\(dockedInteractionSurface.isActive)"
                + " inputTarget=\(dockedInteractionSurface.components[InputTargetComponent.self] != nil)"
        )
        recordDockedInputTargetSceneProbe(in: content)
    }

#if DEBUG
    private func installDockedHitTestProbes(
        beside entity: Entity,
        screenSize: SIMD2<Float>
    ) {
        guard let anchor = entity.parent else { return }

        PlaybackDockedInteractionSurface.install(
            dockedChildFrontProbe,
            on: entity,
            screenSize: screenSize
        )
        dockedChildFrontProbe.name =
            PlaybackDockedInteractionSurface.childFrontProbeName
        dockedChildFrontProbe.position = [0, 0, -0.10]

        PlaybackDockedInteractionSurface.configure(
            dockedAnchorFrontProbe,
            screenSize: screenSize
        )
        dockedAnchorFrontProbe.name =
            PlaybackDockedInteractionSurface.anchorFrontProbeName
        dockedAnchorFrontProbe.orientation = entity.orientation
        dockedAnchorFrontProbe.scale = entity.scale
        dockedAnchorFrontProbe.position = entity.position
            + entity.orientation.act([0, 0, -0.05])
        if dockedAnchorFrontProbe.parent !== anchor {
            anchor.addChild(dockedAnchorFrontProbe)
        }

        let hierarchy =
            "child=\(dockedChildFrontProbe.name)"
                + " childWorldPosition=\(dockedChildFrontProbe.position(relativeTo: nil))"
                + " childActive=\(dockedChildFrontProbe.isActive)"
                + " sibling=\(dockedAnchorFrontProbe.name)"
                + " siblingWorldPosition=\(dockedAnchorFrontProbe.position(relativeTo: nil))"
                + " siblingActive=\(dockedAnchorFrontProbe.isActive)"
        guard presentationObservation.shouldLogSurfaceReadiness(
            reason: "dockedHitTestProbeHierarchy",
            signature: hierarchy
        ) else { return }
        appModel.recordSurfaceInputProbe(
            "dockedHitTestProbe hierarchy \(hierarchy)"
        )
    }

    private func removeDockedHitTestProbes() {
        dockedAnchorFrontProbe.removeFromParent()
        dockedChildFrontProbe.removeFromParent()
    }
#endif

    private func recordDockedInteractionSurfaceAssemblyProbe(_ state: String) {
        guard presentationObservation.shouldLogSurfaceReadiness(
            reason: "dockedInteractionSurfaceAssembly",
            signature: state
        ) else { return }
        appModel.recordSurfaceInputProbe(
            "dockedInputSurface assembly=\(state)"
        )
    }

    private func recordDockedInputTargetSceneProbe(
        in content: RealityViewContent
    ) {
        var entries: [String] = []
        func visit(_ entity: Entity, path: String) {
            let name = entity.name.isEmpty ? "unnamed" : entity.name
            let nextPath = path + "/" + name
            if entity.components[InputTargetComponent.self] != nil {
                let collisionExtents = entity.components[CollisionComponent.self]?
                    .shapes
                    .map { String(describing: $0.bounds.extents) }
                    .joined(separator: ",")
                    ?? "none"
                entries.append(
                    "path=\(nextPath)"
                        + " entity=\(ObjectIdentifier(entity))"
                        + " active=\(entity.isActive)"
                        + " enabled=\(entity.isEnabled)"
                        + " worldPosition=\(entity.position(relativeTo: nil))"
                        + " worldOrientation=\(entity.orientation(relativeTo: nil))"
                        + " worldScale=\(entity.scale(relativeTo: nil))"
                        + " collisionExtents=\(collisionExtents)"
                )
            }
            for child in entity.children {
                visit(child, path: nextPath)
            }
        }
        for (index, root) in content.entities.enumerated() {
            visit(root, path: "root[\(index)]")
        }
        entries.sort()
        let signature = entries.joined(separator: "|")
        guard presentationObservation.shouldLogSurfaceReadiness(
            reason: "dockedInputTargetScene",
            signature: signature
        ) else { return }
        appModel.recordSurfaceInputProbe(
            "dockedInputTargetScene count=\(entries.count)"
        )
        for entry in entries {
            appModel.recordSurfaceInputProbe(
                "dockedInputTarget entity \(entry)"
            )
        }
    }
}

private enum EnvironmentSceneEffectError: LocalizedError {
    case skyboxMissing

    var errorDescription: String? {
        "The environment resource does not contain its skybox entity."
    }
}
