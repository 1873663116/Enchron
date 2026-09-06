import AVFoundation
@testable import Playback
import RealityKit
import RealityKitContent
import XCTest
@testable import Enchron

nonisolated final class PlaybackRealityPresenterTests: XCTestCase {
    @MainActor
    private func loadAuthoredWorld() async throws -> Entity {
        try await Entity(
            named: EnvironmentSceneMapping.worldSceneName,
            in: realityKitContentBundle
        )
    }

    @MainActor
    func testDockingWorldCanLoadFromProductResources() async throws {
        let world = try await loadAuthoredWorld()
        let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertFalse(world.name.isEmpty)
        XCTAssertEqual(anchor.name, PlaybackSurfaceAnchorResolver.canonicalName)
        XCTAssertNil(anchor.components[ModelComponent.self])
        XCTAssertTrue(anchor.children.allSatisfy { $0.components[ModelComponent.self] == nil })
    }

    @MainActor
    func testScenicEnvironmentReplacesSkyboxWithTintedPlaceholder() async throws {
        let world = try await loadAuthoredWorld()
        let skybox = try XCTUnwrap(
            world.findEntity(named: EnvironmentSceneAppearanceApplier.skyboxName)
        )
        let playbackAnchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertEqual(
            EnvironmentSceneAppearanceApplier.apply(
                environment: .scenicOne,
                effect: .dark,
                to: world
            ),
            EnvironmentSceneAppearanceApplier.darkSkyboxOpacity
        )
        XCTAssertFalse(skybox.isEnabled)
        XCTAssertNotNil(
            world.findEntity(named: EnvironmentSceneAppearanceApplier.scenicPlaceholderName)
        )
        XCTAssertEqual(
            world.findEntity(
                named: EnvironmentSceneAppearanceApplier.scenicPlaceholderName
            )?.components[OpacityComponent.self]?.opacity,
            EnvironmentSceneAppearanceApplier.darkSkyboxOpacity
        )
        XCTAssertNil(playbackAnchor.components[OpacityComponent.self])
    }

    @MainActor
    func testSkyboxRestoresTheProductResourceWithoutAnEffect() async throws {
        let world = try await loadAuthoredWorld()
        let skybox = try XCTUnwrap(
            world.findEntity(named: EnvironmentSceneAppearanceApplier.skyboxName)
        )

        _ = EnvironmentSceneAppearanceApplier.apply(
            environment: .scenicThree,
            effect: .light,
            to: world
        )

        XCTAssertEqual(
            EnvironmentSceneAppearanceApplier.apply(
                environment: .skybox,
                effect: nil,
                to: world
            ),
            1
        )
        XCTAssertTrue(skybox.isEnabled)
        XCTAssertNil(
            world.findEntity(named: EnvironmentSceneAppearanceApplier.scenicPlaceholderName)
        )
    }

    @MainActor
    func testClearingEnvironmentDisablesEveryEnvironmentBackdrop() async throws {
        let world = try await loadAuthoredWorld()
        let skybox = try XCTUnwrap(
            world.findEntity(named: EnvironmentSceneAppearanceApplier.skyboxName)
        )

        _ = EnvironmentSceneAppearanceApplier.apply(
            environment: .scenicOne,
            effect: .light,
            to: world
        )
        let placeholder = try XCTUnwrap(
            world.findEntity(named: EnvironmentSceneAppearanceApplier.scenicPlaceholderName)
        )

        EnvironmentSceneAppearanceApplier.clear(in: world)

        XCTAssertFalse(skybox.isEnabled)
        XCTAssertFalse(placeholder.isEnabled)
    }

    @MainActor
    func testLegacyPlaybackSurfaceIsMigratedAndStrippedOfGeometry() throws {
        let world = Entity()
        let legacy = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1),
            materials: [SimpleMaterial()]
        )
        legacy.name = PlaybackSurfaceAnchorResolver.legacyName
        let legacyChild = ModelEntity(
            mesh: .generatePlane(width: 1, depth: 1),
            materials: [SimpleMaterial()]
        )
        legacy.addChild(legacyChild)
        world.addChild(legacy)

        let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertTrue(anchor === legacy)
        XCTAssertEqual(anchor.name, PlaybackSurfaceAnchorResolver.canonicalName)
        XCTAssertNil(anchor.components[ModelComponent.self])
        XCTAssertNil(legacyChild.components[ModelComponent.self])
    }

    @MainActor
    func testWindowBindsTheActiveRendererToVideoPlayerComponent() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .window))
        XCTAssertNil(entity.components[ModelComponent.self])
        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .portal)
        XCTAssertEqual(component.desiredSpatialVideoMode, .screen)
    }

    @MainActor
    func testRepeatedWindowConfigurationReusesTheExistingVideoPlayerComponent() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        var firstComponent = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        firstComponent.desiredViewingMode = .stereo
        entity.components.set(firstComponent)

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: true
        )

        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === firstComponent.videoRenderer)
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredViewingMode, .stereo)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .portal)
        XCTAssertEqual(component.desiredSpatialVideoMode, .spatial)
    }

    @MainActor
    func testWindowSourceRequestsProgressiveOnItsExistingRendererBinding() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false,
            requestsProgressiveImmersiveViewingMode: true
        )

        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .progressive)
    }

    @MainActor
    func testReapplyingDesiredModesAfterSceneActivationKeepsTheExistingRendererBinding() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        var configuredComponent = try XCTUnwrap(
            entity.components[VideoPlayerComponent.self]
        )
        configuredComponent.desiredViewingMode = .stereo
        entity.components.set(configuredComponent)

        PlaybackRealityPresenter.reapplyDesiredModesAfterSceneActivation(
            entity,
            presentation: .panorama,
            requestsSpatialVideoMode: true
        )

        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredViewingMode, .stereo)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .progressive)
        XCTAssertEqual(component.desiredSpatialVideoMode, .spatial)
    }

    @MainActor
    func testCrossRealityViewHandoffKeepsDepartingEntityUntilSceneDisappears() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let spatialRenderer = AVSampleBufferVideoRenderer()
        let store = PlaybackVideoEntityStore()
        let windowEntity = store.entity(for: renderer, presentation: .window)
        PlaybackRealityPresenter.configure(
            windowEntity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        let spatialEntity = store.entity(for: spatialRenderer, presentation: .docked)
        PlaybackRealityPresenter.configure(
            spatialEntity,
            renderer: spatialRenderer,
            presentation: .docked,
            requestsSpatialVideoMode: false
        )

        XCTAssertFalse(windowEntity === spatialEntity)
        XCTAssertNotNil(windowEntity.components[VideoPlayerComponent.self])
        let transition = PlaybackPresentationTransition(
            previousPresentation: .window,
            targetPresentation: .docked,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        XCTAssertTrue(
            store.hostedEntity(for: .window, during: transition) === windowEntity
        )
        XCTAssertTrue(
            store.hostedEntity(for: .docked, during: transition) === spatialEntity
        )
        XCTAssertTrue(
            try XCTUnwrap(spatialEntity.components[VideoPlayerComponent.self])
                .videoRenderer === spatialRenderer
        )

        store.releaseDepartingEntity()
        XCTAssertNil(windowEntity.components[VideoPlayerComponent.self])
    }

    @MainActor
    func testRealityKitContentTypeResetsForReplacementTechnicalSession() {
        let store = PlaybackVideoEntityStore()
        let renderer = AVSampleBufferVideoRenderer()
        let sourceRoot = Entity()
        let targetRoot = Entity()
        let scope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            technicalSessionID: "technical-a"
        )
        let sourceEntity = store.entity(for: renderer, presentation: .window)
        sourceRoot.addChild(sourceEntity)
        store.synchronizeRealityKitContentTypeScope(scope)
        store.recordRealityKitContentType("equirectangular", for: scope)

        let replacementRenderer = AVSampleBufferVideoRenderer()
        let replacementScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            technicalSessionID: "technical-b"
        )
        let targetEntity = store.entity(
            for: replacementRenderer,
            presentation: .panorama
        )
        targetRoot.addChild(targetEntity)
        store.synchronizeRealityKitContentTypeScope(replacementScope)

        XCTAssertFalse(sourceEntity === targetEntity)
        XCTAssertTrue(targetEntity.parent === targetRoot)
        XCTAssertEqual(store.realityKitContentType, "unobserved")
        XCTAssertEqual(store.realityKitContentTypeScope, replacementScope)
    }

    @MainActor
    func testRealityKitContentTypeResetsForTechnicalSessionAndRejectsStaleEvents() {
        let store = PlaybackVideoEntityStore()
        let originalScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            technicalSessionID: "technical-a"
        )
        let replacementTechnicalScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            technicalSessionID: "technical-b"
        )
        let replacementSessionScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-b"
        )

        store.synchronizeRealityKitContentTypeScope(originalScope)
        store.recordRealityKitContentType("rectilinear", for: originalScope)
        store.synchronizeRealityKitContentTypeScope(replacementTechnicalScope)
        XCTAssertEqual(store.realityKitContentType, "unobserved")

        store.recordRealityKitContentType("rectilinear", for: originalScope)
        XCTAssertEqual(store.realityKitContentType, "unobserved")
        store.recordRealityKitContentType(
            "rectilinear",
            for: replacementTechnicalScope
        )
        XCTAssertEqual(store.realityKitContentType, "rectilinear")

        store.synchronizeRealityKitContentTypeScope(replacementTechnicalScope)
        XCTAssertEqual(
            store.realityKitContentType,
            "rectilinear",
            "Republishing the same technical-session scope must keep its event."
        )

        store.recordRealityKitContentType(
            "equirectangular",
            forTechnicalSessionID: "technical-a"
        )
        XCTAssertEqual(
            store.realityKitContentType,
            "rectilinear",
            "A callback captured by the retired technical session must be rejected."
        )
        store.recordRealityKitContentType(
            "equirectangular",
            forTechnicalSessionID: "technical-b"
        )
        XCTAssertEqual(store.realityKitContentType, "equirectangular")

        store.synchronizeRealityKitContentTypeScope(replacementSessionScope)
        XCTAssertEqual(store.realityKitContentType, "unobserved")
        store.recordRealityKitContentType(
            "rectilinear",
            for: replacementTechnicalScope
        )
        store.recordRealityKitContentType(
            "rectilinear",
            forTechnicalSessionID: "technical-b"
        )
        XCTAssertEqual(store.realityKitContentType, "unobserved")
    }

    @MainActor
    func testRealityKitContentTypeChangePublishesItsExactTechnicalSessionScope() {
        let store = PlaybackVideoEntityStore()
        let scope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a"
        )
        var observed: (String, PlaybackRealityKitContentTypeScope)?
        store.onRealityKitContentTypeChanged = { contentType, scope in
            observed = (contentType, scope)
        }

        store.synchronizeRealityKitContentTypeScope(scope)
        store.recordRealityKitContentType("equirectangular", for: scope)

        XCTAssertEqual(observed?.0, "equirectangular")
        XCTAssertEqual(observed?.1, scope)
    }

    @MainActor
    func testReleasingASceneEntityRemovesItsVideoRendererBinding() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        PlaybackRealityPresenter.releaseVideoRenderer(from: entity)

        XCTAssertNil(entity.components[VideoPlayerComponent.self])
    }

    @MainActor
    func testPanoramaReturnWaitsWhenPortalModeIsNotYetReported() {
        let retry = PlaybackModeRequestRetry()
        let entity = Entity()
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let first = retry.recoveryAction(
            entity: entity,
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: true,
            now: startedAt
        )
        let second = retry.recoveryAction(
            entity: entity,
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: true,
            now: startedAt.addingTimeInterval(0.6)
        )

        guard case .none = first else {
            return XCTFail("A missing current mode must not replace the new component state.")
        }
        guard case .none = second else {
            return XCTFail("RealityKit must be allowed to finish classifying the new target.")
        }
    }

    @MainActor
    func testPanoramaReturnNeverUsesEntityReplacementAsModeRecovery() {
        let retry = PlaybackModeRequestRetry()
        let initialEntity = Entity()
        let replacementEntity = Entity()
        let startedAt = Date(timeIntervalSince1970: 1_000)

        _ = retry.recoveryAction(
            entity: initialEntity,
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: true,
            now: startedAt
        )
        let firstRetry = retry.recoveryAction(
            entity: initialEntity,
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: true,
            now: startedAt.addingTimeInterval(0.6)
        )
        _ = retry.recoveryAction(
            entity: replacementEntity,
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: true,
            now: startedAt.addingTimeInterval(0.7)
        )
        let secondRetry = retry.recoveryAction(
            entity: replacementEntity,
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: true,
            now: startedAt.addingTimeInterval(1.3)
        )

        guard case .none = firstRetry else {
            return XCTFail("A missing Portal mode must not rewrite the component.")
        }
        guard case .none = secondRetry else {
            return XCTFail("Changing the caller's Entity must not create a mode rewrite path.")
        }
    }

    @MainActor
    func testOrdinaryWindowDoesNotRecoverWhilePortalModeIsInitiallyUnreported() {
        let retry = PlaybackModeRequestRetry()

        let action = retry.recoveryAction(
            entity: Entity(),
            presentation: .window,
            desiredImmersiveViewingMode: "portal",
            actualImmersiveViewingMode: nil,
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            requiresImmersiveViewingModeSettlement: false
        )

        guard case .none = action else {
            return XCTFail("An ordinary Window must wait for its first frame without rebuilding.")
        }
    }

    @MainActor
    func testPanoramaReappliesAnUnsettledSpatialVideoMode() {
        let retry = PlaybackModeRequestRetry()

        let action = retry.recoveryAction(
            entity: Entity(),
            presentation: .panorama,
            desiredImmersiveViewingMode: "progressive",
            actualImmersiveViewingMode: "progressive",
            desiredSpatialVideoMode: "spatial",
            actualSpatialVideoMode: "screen"
        )

        guard case .requestModesAgain = action else {
            return XCTFail(
                "Panorama must request Spatial mode again until RealityKit reports it."
            )
        }
    }

    @MainActor
    func testPanoramaDoesNotUseModeRequestsToRepairInvalidContentType() {
        let retry = PlaybackModeRequestRetry()
        let entity = Entity()
        let startedAt = Date(timeIntervalSince1970: 1_000)

        let first = retry.recoveryAction(
            entity: entity,
            presentation: .panorama,
            desiredImmersiveViewingMode: "progressive",
            actualImmersiveViewingMode: "progressive",
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            contentTypeMatchesProjection: false,
            now: startedAt
        )
        let second = retry.recoveryAction(
            entity: entity,
            presentation: .panorama,
            desiredImmersiveViewingMode: "progressive",
            actualImmersiveViewingMode: "progressive",
            desiredSpatialVideoMode: "screen",
            actualSpatialVideoMode: "screen",
            contentTypeMatchesProjection: false,
            now: startedAt.addingTimeInterval(0.6)
        )

        guard case .none = first else {
            return XCTFail("Mode requests cannot repair renderer format signaling.")
        }
        guard case .none = second else {
            return XCTFail("Invalid content type must not churn the existing component.")
        }
    }

    @MainActor
    func testAChangedRendererCreatesANewVideoEntityWithinOneRealityView() {
        let store = PlaybackVideoEntityStore()
        let first = store.entity(for: AVSampleBufferVideoRenderer())
        let second = store.entity(for: AVSampleBufferVideoRenderer())

        XCTAssertFalse(first === second)
    }

    @MainActor
    func testRendererTargetBindingWaitsForRealityKitCommitBeforeRestartingDelivery() async {
        let gate = PlaybackRendererTargetBindingGate(
            settlementDelay: .milliseconds(50)
        )
        var didRestartDelivery = false

        gate.schedule {
            didRestartDelivery = true
        }
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertFalse(
            didRestartDelivery,
            "A component commit cannot synchronously restart sample delivery."
        )

        try? await Task.sleep(for: .milliseconds(70))
        XCTAssertTrue(didRestartDelivery)
    }

    @MainActor
    func testRendererTargetBindingIsNotPostponedByPanoramaComponentChanges() async {
        let gate = PlaybackRendererTargetBindingGate(
            settlementDelay: .milliseconds(50)
        )
        var didConfirmTarget = false

        gate.schedule {
            didConfirmTarget = true
        }
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(15))
            gate.schedule {
                didConfirmTarget = true
            }
        }
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(
            didConfirmTarget,
            "Later VideoPlayerComponent changes must not postpone the first bounded target confirmation."
        )
    }

    @MainActor
    func testNewRendererPreservesDepartingEntityAndCarriesItsRevision() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let store = PlaybackVideoEntityStore()
        let entity = store.entity(
            for: renderer,
            presentation: .window,
            videoComponentRevision: 0
        )
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        XCTAssertNotNil(entity.components[VideoPlayerComponent.self])

        let replacementRenderer = AVSampleBufferVideoRenderer()
        let revisedEntity = store.entity(
            for: replacementRenderer,
            presentation: .window,
            videoComponentRevision: 1
        )

        XCTAssertFalse(revisedEntity === entity)
        XCTAssertNotNil(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(store.departingEntity === entity)
        XCTAssertTrue(
            store.hasApplied(
                videoComponentRevision: 1,
                to: replacementRenderer,
                presentation: .window
            )
        )
    }

    @MainActor
    func testRevisionAloneNeverRebindsTheSameRenderer() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let store = PlaybackVideoEntityStore()
        let entity = store.entity(
            for: renderer,
            presentation: .window,
            videoComponentRevision: 0
        )
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        _ = store.entity(
            for: renderer,
            presentation: .window,
            videoComponentRevision: 1
        )

        XCTAssertTrue(
            try XCTUnwrap(entity.components[VideoPlayerComponent.self])
                .videoRenderer === renderer
        )
        XCTAssertTrue(
            store.hasApplied(
                videoComponentRevision: 1,
                to: renderer,
                presentation: .window
            )
        )
    }

    @MainActor
    func testWindowVideoSurfaceOmitsRealityKitHitTargetsSoSwiftUIOwnsTaps() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        XCTAssertNil(entity.components[InputTargetComponent.self])
        XCTAssertNil(entity.components[CollisionComponent.self])
        let accessibility = try XCTUnwrap(
            entity.components[AccessibilityComponent.self]
        )
        XCTAssertTrue(accessibility.isAccessibilityElement)
        XCTAssertTrue(accessibility.systemActions.contains(.activate))
        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .window))
    }

    @MainActor
    func testDockedVideoSurfaceOmitsRealityKitHitTargets() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        entity.components.set(InputTargetComponent())
        entity.components.set(
            CollisionComponent(shapes: [.generateBox(size: [1.8, 1, 0.01])])
        )

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .docked,
            requestsSpatialVideoMode: false
        )

        XCTAssertNil(entity.components[InputTargetComponent.self])
        XCTAssertNil(entity.components[CollisionComponent.self])
        let accessibility = try XCTUnwrap(
            entity.components[AccessibilityComponent.self]
        )
        XCTAssertTrue(accessibility.isAccessibilityElement)
        XCTAssertNotNil(accessibility.label)
        XCTAssertTrue(accessibility.systemActions.contains(.activate))
        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .docked))
    }

    @MainActor
    func testDockedUsesInteractionPlateSizedFromVideoAspectAndScreenScale() throws {
        let videoEntity = Entity()
        videoEntity.scale = .init(repeating: 1.75)
        let store = PlaybackVideoEntityStore()
        let interactionSurface = store.dockedInteractionSurface

        PlaybackDockedInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1]
        )

        XCTAssertTrue(interactionSurface.parent === videoEntity)
        XCTAssertTrue(PlaybackDockedInteractionSurface.contains(interactionSurface))
        XCTAssertGreaterThan(PlaybackDockedInteractionSurface.frontOffset, 0)
        XCTAssertEqual(
            interactionSurface.position,
            [0, 0, PlaybackDockedInteractionSurface.frontOffset]
        )
        XCTAssertNotNil(interactionSurface.components[InputTargetComponent.self])
        let collision = try XCTUnwrap(
            interactionSurface.components[CollisionComponent.self]
        )
        let shape = try XCTUnwrap(collision.shapes.first)
        XCTAssertEqual(
            shape.bounds.extents,
            [2.4, 1, PlaybackDockedInteractionSurface.thickness]
        )
        XCTAssertEqual(
            interactionSurface.scale(relativeTo: nil),
            [1.75, 1.75, 1.75]
        )
    }

    @MainActor
    func testWindowUsesInteractionSurfaceSizedFromVideoScreen() throws {
        let videoEntity = Entity()
        videoEntity.scale = .init(repeating: 0.8)
        let store = PlaybackVideoEntityStore()
        let interactionSurface = store.windowInteractionSurface

        PlaybackWindowInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1],
            verticalFill: 1,
            occlusion: .none
        )

        XCTAssertTrue(interactionSurface.parent === videoEntity)
        XCTAssertTrue(PlaybackWindowInteractionSurface.contains(interactionSurface))
        XCTAssertGreaterThan(PlaybackWindowInteractionSurface.frontOffset, 0)
        XCTAssertEqual(
            interactionSurface.position,
            [0, 0, PlaybackWindowInteractionSurface.frontOffset]
        )
        XCTAssertNotNil(interactionSurface.components[InputTargetComponent.self])
        let collision = try XCTUnwrap(
            interactionSurface.components[CollisionComponent.self]
        )
        let shape = try XCTUnwrap(collision.shapes.first)
        XCTAssertEqual(
            shape.bounds.extents,
            [2.4, 1, PlaybackWindowInteractionSurface.thickness]
        )
    }

    @MainActor
    func testWindowInteractionSurfaceStopsBelowTheTopChrome() throws {
        let videoEntity = Entity()
        let store = PlaybackVideoEntityStore()
        let interactionSurface = store.windowInteractionSurface

        PlaybackWindowInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1],
            verticalFill: 1,
            occlusion: PlaybackWindowChromeOcclusion(topFraction: 0.2)
        )

        let collision = try XCTUnwrap(
            interactionSurface.components[CollisionComponent.self]
        )
        let shape = try XCTUnwrap(collision.shapes.first)
        XCTAssertEqual(
            shape.bounds.extents,
            [2.4, 0.8, PlaybackWindowInteractionSurface.thickness]
        )
        XCTAssertEqual(
            interactionSurface.position,
            [0, -0.1, PlaybackWindowInteractionSurface.frontOffset]
        )
        XCTAssertEqual(
            interactionSurface.position.y + shape.bounds.extents.y / 2,
            0.3,
            accuracy: 1e-6
        )
    }

    @MainActor
    func testWindowInteractionSurfaceScalesTheCutoutForALetterboxedVideo() throws {
        let videoEntity = Entity()
        let store = PlaybackVideoEntityStore()
        let interactionSurface = store.windowInteractionSurface

        PlaybackWindowInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1],
            verticalFill: 0.5,
            occlusion: PlaybackWindowChromeOcclusion(topFraction: 0.2)
        )

        let collision = try XCTUnwrap(
            interactionSurface.components[CollisionComponent.self]
        )
        let shape = try XCTUnwrap(collision.shapes.first)
        XCTAssertEqual(
            shape.bounds.extents,
            [2.4, 0.6, PlaybackWindowInteractionSurface.thickness]
        )
    }

    @MainActor
    func testWindowInteractionSurfaceKeepsItsColliderWhileASecondaryMenuIsPresented() throws {
        let videoEntity = Entity()
        let store = PlaybackVideoEntityStore()
        let interactionSurface = store.windowInteractionSurface

        PlaybackWindowInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1],
            verticalFill: 1,
            occlusion: PlaybackWindowChromeOcclusion(
                topFraction: 0.2,
                secondaryMenuIsPresented: true
            )
        )

        XCTAssertNotNil(interactionSurface.components[InputTargetComponent.self])
        let collision = try XCTUnwrap(interactionSurface.components[CollisionComponent.self])
        let shape = try XCTUnwrap(collision.shapes.first)
        XCTAssertEqual(
            shape.bounds.extents,
            [2.4, 0.8, PlaybackWindowInteractionSurface.thickness]
        )
    }

    @MainActor
    func testWindowInteractionSurfaceRestoresFullCoverageWhenChromeHides() throws {
        let videoEntity = Entity()
        let store = PlaybackVideoEntityStore()
        let interactionSurface = store.windowInteractionSurface

        PlaybackWindowInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1],
            verticalFill: 1,
            occlusion: PlaybackWindowChromeOcclusion(
                topFraction: 0.2,
                secondaryMenuIsPresented: true
            )
        )
        PlaybackWindowInteractionSurface.install(
            interactionSurface,
            on: videoEntity,
            screenSize: [2.4, 1],
            verticalFill: 1,
            occlusion: .none
        )

        XCTAssertNotNil(interactionSurface.components[InputTargetComponent.self])
        let collision = try XCTUnwrap(
            interactionSurface.components[CollisionComponent.self]
        )
        let shape = try XCTUnwrap(collision.shapes.first)
        XCTAssertEqual(
            shape.bounds.extents,
            [2.4, 1, PlaybackWindowInteractionSurface.thickness]
        )
        XCTAssertEqual(
            interactionSurface.position,
            [0, 0, PlaybackWindowInteractionSurface.frontOffset]
        )
    }

    @MainActor
    func testPanoramaUsesAnIndependentInteractionSurfaceOutsideTheViewerOrigin() {
        let renderer = AVSampleBufferVideoRenderer()
        let videoEntity = Entity()

        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: .panorama,
            requestsSpatialVideoMode: false
        )
        let interactionSurface = PlaybackPanoramaInteractionSurface.makeEntity()

        XCTAssertNil(videoEntity.components[InputTargetComponent.self])
        XCTAssertNil(videoEntity.components[CollisionComponent.self])
        XCTAssertEqual(interactionSurface.children.count, 6)
        for panel in interactionSurface.children {
            XCTAssertTrue(PlaybackPanoramaInteractionSurface.contains(panel))
            XCTAssertNotNil(panel.components[InputTargetComponent.self])
            XCTAssertNotNil(panel.components[CollisionComponent.self])
        }
    }

    @MainActor
    func testEachPresentationHasExactlyOneDirectSurfaceInputOwner() {
        XCTAssertEqual(
            PlaybackSurfaceInputOwnership.owner(for: .window),
            .windowInteractionSurface
        )
        XCTAssertEqual(
            PlaybackSurfaceInputOwnership.owner(for: .portal),
            .windowInteractionSurface
        )
        XCTAssertEqual(
            PlaybackSurfaceInputOwnership.owner(for: .docked),
            .dockedInteractionSurface
        )
        XCTAssertEqual(
            PlaybackSurfaceInputOwnership.owner(for: .panorama),
            .panoramaInteractionSurface
        )
    }

    @MainActor
    func testImmersiveGesturesAcceptOnlyTheirPresentationInteractionSurface() throws {
        let dockedSurface = PlaybackDockedInteractionSurface.makeEntity()
        let panoramaSurface = PlaybackPanoramaInteractionSurface.makeEntity()
        let panoramaPanel = try XCTUnwrap(panoramaSurface.children.first)
        let windowSurface = PlaybackWindowInteractionSurface.makeEntity()
        let unrelatedEntity = Entity()
        unrelatedEntity.name = "EnchronHeadInput.probe"

        XCTAssertTrue(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                windowSurface,
                for: .window
            )
        )
        XCTAssertTrue(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                windowSurface,
                for: .portal
            )
        )
        XCTAssertFalse(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                windowSurface,
                for: .docked
            )
        )
        XCTAssertFalse(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                dockedSurface,
                for: .window
            )
        )
        XCTAssertTrue(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                dockedSurface,
                for: .docked
            )
        )
        XCTAssertFalse(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                panoramaPanel,
                for: .docked
            )
        )
        XCTAssertTrue(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                panoramaPanel,
                for: .panorama
            )
        )
        XCTAssertFalse(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                dockedSurface,
                for: .panorama
            )
        )
        for presentation in PlaybackPresentation.allCases {
            XCTAssertFalse(
                PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                    unrelatedEntity,
                    for: presentation
                )
            )
        }
#if DEBUG
        let debugDockedProbe = Entity()
        debugDockedProbe.name = PlaybackDockedInteractionSurface.childFrontProbeName
        XCTAssertFalse(
            PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                debugDockedProbe,
                for: .docked
            )
        )
#endif
    }

    @MainActor
    func testPanoramaMovesTheSameRendererToVideoPlayerComponent() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .panorama,
            requestsSpatialVideoMode: false
        )

        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .panorama))
        XCTAssertNil(entity.components[ModelComponent.self])
        let component = try XCTUnwrap(entity.components[VideoPlayerComponent.self])
        XCTAssertTrue(component.videoRenderer === renderer)
        XCTAssertEqual(component.desiredImmersiveViewingMode, .progressive)
        XCTAssertEqual(component.desiredSpatialVideoMode, .screen)
    }

}
