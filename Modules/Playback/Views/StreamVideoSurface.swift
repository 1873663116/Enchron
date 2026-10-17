import AVFoundation
import Foundation
import RealityKit
import SwiftUI

@MainActor
private final class StreamVideoSurfaceProbes {
    private var signatures: [String: String] = [:]
    private var emissions: [String: Date] = [:]
    private var sequence = 0

    func line(
        kind: String,
        fact: String,
        heartbeat: TimeInterval,
        now: Date = Date()
    ) -> String? {
        if signatures[kind] == fact {
            guard heartbeat > 0,
                  let lastEmission = emissions[kind],
                  now.timeIntervalSince(lastEmission) >= heartbeat else {
                return nil
            }
        }
        signatures[kind] = fact
        emissions[kind] = now
        sequence += 1
        return "streamSurface#\(sequence) \(fact)"
    }
}

public struct StreamVideoSurface: View {
    public let renderer: AVSampleBufferVideoRenderer
    public let renderRevision: Int
    public let accessibilityIdentifier: String
    public let onSurfaceBinding: (@MainActor (Int, Bool) -> Void)?
    public let onProbe: (@MainActor (String, DebugProbeRetention) -> Void)?

    @State private var videoEntity = Entity()
    @State private var hostMarker: Entity = {
        let entity = Entity()
        entity.name = "EnchronRealityView.streamWindow"
        return entity
    }()
    @State private var hostedRenderer: AVSampleBufferVideoRenderer?
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var updateScheduler = PlaybackRealityViewUpdateScheduler()
    @State private var reattachRequired = false
    @State private var lastObservedHostActive: Bool?
    @State private var reportedSurfaceBinding: Bool?
    @State private var surfaceRefreshTick = 0
    @State private var probes = StreamVideoSurfaceProbes()

    public init(
        renderer: AVSampleBufferVideoRenderer,
        renderRevision: Int,
        accessibilityIdentifier: String = "Stream-Session-video",
        onSurfaceBinding: (@MainActor (Int, Bool) -> Void)? = nil,
        onProbe: (@MainActor (String, DebugProbeRetention) -> Void)? = nil
    ) {
        self.renderer = renderer
        self.renderRevision = renderRevision
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSurfaceBinding = onSurfaceBinding
        self.onProbe = onProbe
    }

    public var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                installHostMarker(into: content)
                armSurfaceActivation(content: content, proxy: geometry)
                scheduleSurfacePass(content: content, proxy: geometry, reason: "make")
            } update: { content in
                installHostMarker(into: content)
                armSurfaceActivation(content: content, proxy: geometry)
                scheduleSurfacePass(content: content, proxy: geometry, reason: "update")
            }
            .frame(depth: WindowPlaybackSurfaceGeometry.flatWindowDepth)
        }
        .frame(depth: WindowPlaybackSurfaceGeometry.flatWindowDepth)
        .task(id: surfaceReadinessKey) {
            await retrySurfaceAttachment()
        }
        .onDisappear {
            releaseSurface(reason: "viewDisappeared")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var surfaceReadinessKey: String {
        [
            "revision\(renderRevision)",
            String(describing: ObjectIdentifier(renderer)),
            hostMarker.isActive ? "hostActive" : "hostInactive"
        ].joined(separator: "|")
    }

    private struct SurfaceFacts {
        let hostIsActive: Bool
        let entityIsInserted: Bool
        let entityIsActive: Bool
        let componentIsBound: Bool

        var isSatisfied: Bool {
            hostIsActive && entityIsInserted && entityIsActive && componentIsBound
        }

        var summary: String {
            "hostActive=\(hostIsActive)"
                + " inserted=\(entityIsInserted)"
                + " entityActive=\(entityIsActive)"
                + " bound=\(componentIsBound)"
        }
    }

    private var surfaceFacts: SurfaceFacts {
        SurfaceFacts(
            hostIsActive: hostMarker.isActive,
            entityIsInserted: videoEntity.parent != nil,
            entityIsActive: videoEntity.isActive,
            componentIsBound: PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: .window
            )
        )
    }

    private func installHostMarker(into content: RealityViewContent) {
        guard content.entities.contains(where: { $0 === hostMarker }) == false else {
            return
        }
        content.add(hostMarker)
        probe(
            kind: "hostMarker",
            fact: "hostMarkerInserted active=\(hostMarker.isActive)"
                + " revision=\(renderRevision)"
                + " entity=\(identity(hostMarker))",
            retention: .evidence
        )
    }

    private func armSurfaceActivation(content: RealityViewContent, proxy: GeometryProxy3D) {
        surfaceActivation.observe(videoEntity, in: content) {
            scheduleSurfacePass(content: content, proxy: proxy, reason: "activation")
        }
    }

    private func scheduleSurfacePass(
        content: RealityViewContent,
        proxy: GeometryProxy3D,
        reason: String
    ) {
        updateScheduler.schedule {
            guard Task.isCancelled == false else { return }
            maintainSurface(content: content, proxy: proxy, reason: reason)
        }
    }

    @MainActor
    private func maintainSurface(
        content: RealityViewContent,
        proxy: GeometryProxy3D,
        reason: String
    ) {
        installHostMarker(into: content)
        synchronizeVideoEntity(in: content)
        let facts = surfaceFacts
        guard facts.hostIsActive else {
            reportSurfaceBinding(false)
            probe(
                kind: "presence",
                fact: "presence reason=\(reason) outcome=hostInactive \(facts.summary)"
                    + " revision=\(renderRevision)",
                heartbeat: 2,
                retention: .diagnostic
            )
            return
        }
        guard content.entities.contains(where: { $0 === videoEntity }) else {
            videoEntity.name = "EnchronVideo.streamWindow#\(renderRevision)"
            content.add(videoEntity)
            probe(
                kind: "entityInserted",
                fact: "entityInserted \(facts.summary)"
                    + " revision=\(renderRevision)"
                    + " entity=\(identity(videoEntity))",
                retention: .evidence
            )
            armSurfaceActivation(content: content, proxy: proxy)
            return
        }
        guard facts.entityIsActive else {
            reportSurfaceBinding(false)
            probe(
                kind: "presence",
                fact: "presence reason=\(reason) outcome=entityInactive \(facts.summary)"
                    + " revision=\(renderRevision)",
                heartbeat: 2,
                retention: .diagnostic
            )
            return
        }
        let rewriteReason: String?
        if facts.componentIsBound {
            rewriteReason = reattachRequired ? "hostActivationChanged" : nil
        } else {
            rewriteReason = "unbound"
        }
        if reattachRequired {
            reattachRequired = false
        }
        if let rewriteReason {
            PlaybackRealityPresenter.releaseVideoRenderer(from: videoEntity)
            probe(
                kind: "componentRelease",
                fact: "componentRelease reason=\(rewriteReason) \(facts.summary)"
                    + " revision=\(renderRevision)"
                    + " entity=\(identity(videoEntity))",
                retention: .evidence
            )
        }
        let write = PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        if write != .unchanged || rewriteReason != nil {
            probe(
                kind: "componentWrite",
                fact: "componentWrite write=\(write.rawValue)"
                    + " reason=\(rewriteReason ?? "reconcile")"
                    + " \(facts.summary)"
                    + " revision=\(renderRevision)"
                    + " entity=\(identity(videoEntity))",
                retention: .evidence
            )
        }
        updateLayout(content: content, proxy: proxy)
        reportSurfaceBinding(
            PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: .window
            )
        )
        probeSurfaceState()
    }

    private func synchronizeVideoEntity(in content: RealityViewContent) {
        guard let hostedRenderer else {
            self.hostedRenderer = renderer
            videoEntity.name = "EnchronVideo.streamWindow#\(renderRevision)"
            probe(
                kind: "rendererAdopted",
                fact: "rendererAdopted revision=\(renderRevision)"
                    + " renderer=\(identity(renderer))"
                    + " entity=\(identity(videoEntity))",
                retention: .evidence
            )
            return
        }
        guard hostedRenderer !== renderer else { return }
        let retired = videoEntity
        let retiredWasBound = PlaybackRealityPresenter.isBound(
            retired,
            to: hostedRenderer,
            presentation: .window
        )
        let retiredWasInContent = content.entities.contains { $0 === retired }
        PlaybackRealityPresenter.releaseVideoRenderer(from: retired)
        if retiredWasInContent {
            content.remove(retired)
        }
        videoEntity = Entity()
        self.hostedRenderer = renderer
        reattachRequired = true
        reportSurfaceBinding(false)
        probe(
            kind: "rendererChanged",
            fact: "rendererChanged retiredWasBound=\(retiredWasBound)"
                + " retiredWasInContent=\(retiredWasInContent)"
                + " revision=\(renderRevision)"
                + " renderer=\(identity(renderer))"
                + " entity=\(identity(videoEntity))",
            retention: .evidence
        )
    }

    private func updateLayout(content: RealityViewContent, proxy: GeometryProxy3D) {
        guard let component = videoEntity.components[VideoPlayerComponent.self] else {
            return
        }
        let screenSize = component.playerScreenSize
        let resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : WindowPlaybackSurfaceGeometry.defaultSurfaceSize
        let sceneBounds = content.convert(
            proxy.frame(in: .local),
            from: .local,
            to: .scene
        )
        guard let layout = WindowPlaybackSurfaceGeometry.layout(
            surfaceSize: resolvedScreenSize,
            sceneCenter: sceneBounds.center,
            sceneExtents: sceneBounds.extents
        ) else {
            probe(
                kind: "layoutRejected",
                fact: "layoutRejected screenSize=\(resolvedScreenSize)"
                    + " sceneExtents=\(sceneBounds.extents)"
                    + " revision=\(renderRevision)",
                retention: .evidence
            )
            return
        }
        PlaybackSurfacePlacement.window(
            videoEntity,
            sceneCenter: layout.sceneCenter
        )
        videoEntity.scale = .init(repeating: layout.scale)
        probe(
            kind: "layout",
            fact: "layout sceneCenter=\(layout.sceneCenter)"
                + " available=\(layout.availableSize)"
                + " rendered=\(layout.renderedSize)"
                + " screenSize=\(resolvedScreenSize)"
                + " scale=\(layout.scale)"
                + " sceneExtents=\(sceneBounds.extents)"
                + " revision=\(renderRevision)",
            retention: .evidence
        )
    }

    private func reportSurfaceBinding(_ isBound: Bool) {
        guard reportedSurfaceBinding != isBound else { return }
        reportedSurfaceBinding = isBound
        probe(
            kind: "binding",
            fact: "surfaceBinding bound=\(isBound)"
                + " revision=\(renderRevision)"
                + " renderer=\(identity(renderer))"
                + " entity=\(identity(videoEntity))",
            retention: .evidence
        )
        onSurfaceBinding?(renderRevision, isBound)
    }

    private func probeSurfaceState() {
        let component = videoEntity.components[VideoPlayerComponent.self]
        let facts = [
            "component=\(component == nil ? "none" : "present")",
            "rendering=\(component.map { String(describing: $0.currentRenderingStatus) } ?? "none")",
            "immersive=\(component.flatMap { $0.immersiveViewingMode }.map { String(describing: $0) } ?? "none")",
            "wantImmersive=\(component.map { String(describing: $0.desiredImmersiveViewingMode) } ?? "none")",
            "spatial=\(component.map { String(describing: $0.spatialVideoMode) } ?? "none")",
            "screenSize=\(component?.playerScreenSize ?? .zero)",
            "rendererStatus=\(String(describing: renderer.status))",
            "rendererError=\(renderer.error?.localizedDescription ?? "none")",
            "readyForMoreMediaData=\(renderer.isReadyForMoreMediaData)",
            "requiresFlush=\(renderer.requiresFlushToResumeDecoding)",
            "displayedPixelBuffer=\(renderer.displayedPixelBuffer() != nil)"
        ].joined(separator: " ")
        probe(
            kind: "renderer",
            fact: "rendererState \(facts) revision=\(renderRevision)",
            heartbeat: 2,
            retention: .diagnostic
        )
    }

    @MainActor
    private func retrySurfaceAttachment() async {
        recordAttachmentFacts(reason: "enter")
        for _ in 0..<PlaybackSurfaceActivation.maximumRetryCountForView {
            guard Task.isCancelled == false else { return }
            if lastObservedHostActive != hostMarker.isActive {
                lastObservedHostActive = hostMarker.isActive
                reattachRequired = true
                probe(
                    kind: "hostActivation",
                    fact: "hostActivationChanged active=\(hostMarker.isActive)"
                        + " revision=\(renderRevision)",
                    retention: .evidence
                )
            }
            let facts = surfaceFacts
            if facts.isSatisfied, reattachRequired == false {
                recordAttachmentFacts(reason: "settled", facts: facts)
                return
            }
            recordAttachmentFacts(reason: "reattaching", facts: facts)
            surfaceRefreshTick &+= 1
            surfaceActivation.requestRetry()
            try? await Task.sleep(for: PlaybackSurfaceActivation.retryIntervalForView)
        }
        recordAttachmentFacts(reason: "unsettled")
    }

    private func recordAttachmentFacts(
        reason: String,
        facts: SurfaceFacts? = nil
    ) {
        let facts = facts ?? surfaceFacts
        probe(
            kind: "attachment",
            fact: "attachment \(reason) \(facts.summary)"
                + " revision=\(renderRevision)"
                + " renderer=\(identity(renderer))"
                + " entity=\(identity(videoEntity))",
            retention: reason == "reattaching" ? .diagnostic : .evidence
        )
    }

    private func releaseSurface(reason: String) {
        updateScheduler.cancel()
        surfaceActivation.cancel()
        reattachRequired = false
        if PlaybackRealityPresenter.isBound(
            videoEntity,
            to: renderer,
            presentation: .window
        ) {
            PlaybackRealityPresenter.releaseVideoRenderer(from: videoEntity)
        }
        videoEntity.removeFromParent()
        reportSurfaceBinding(false)
        probe(
            kind: "disappear",
            fact: "surfaceReleased reason=\(reason)"
                + " revision=\(renderRevision)"
                + " entity=\(identity(videoEntity))",
            retention: .evidence
        )
    }

    private func probe(
        kind: String,
        fact: @autoclosure () -> String,
        heartbeat: TimeInterval = 0,
        retention: DebugProbeRetention = .evidence
    ) {
        guard let line = probes.line(
            kind: kind,
            fact: fact(),
            heartbeat: heartbeat
        ) else {
            return
        }
        SurfaceInputProbes.record(line, retention: retention)
        onProbe?(line, retention)
    }

    private func identity(_ entity: Entity) -> String {
        let name = entity.name.isEmpty ? "unnamed" : entity.name
        return "\(name)|\(ObjectIdentifier(entity))"
    }

    private func identity(_ renderer: AVSampleBufferVideoRenderer) -> String {
        String(describing: ObjectIdentifier(renderer))
    }
}
