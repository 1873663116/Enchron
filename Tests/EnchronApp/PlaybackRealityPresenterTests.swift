import AVFoundation
import PlaybackPresentation
import RealityKit
import XCTest
@testable import Enchron

nonisolated final class PlaybackRealityPresenterTests: XCTestCase {
    @MainActor
    func testDockingWorldCanLoadFromProductResources() async throws {
        let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
        let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertFalse(world.name.isEmpty)
        XCTAssertEqual(anchor.name, PlaybackSurfaceAnchorResolver.canonicalName)
        XCTAssertNil(anchor.components[ModelComponent.self])
        XCTAssertTrue(anchor.children.allSatisfy { $0.components[ModelComponent.self] == nil })
    }

    @MainActor
    func testScenicEnvironmentReplacesSkyboxWithTintedPlaceholder() async throws {
        let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
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
        let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
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
        let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
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
    func testPresentationsReuseOneVideoEntityAndOneRendererBinding() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let store = PlaybackVideoEntityStore()
        let windowEntity = store.entity(for: renderer)
        PlaybackRealityPresenter.configure(
            windowEntity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        let spatialEntity = store.entity(for: renderer)
        PlaybackRealityPresenter.configure(
            spatialEntity,
            renderer: renderer,
            presentation: .docked,
            requestsSpatialVideoMode: false
        )

        XCTAssertTrue(windowEntity === spatialEntity)
        XCTAssertTrue(
            try XCTUnwrap(spatialEntity.components[VideoPlayerComponent.self])
                .videoRenderer === renderer
        )
    }

    @MainActor
    func testRealityKitContentTypeSurvivesMovingTheStableEntityBetweenRoots() {
        let store = PlaybackVideoEntityStore()
        let sourceRoot = Entity()
        let targetRoot = Entity()
        let scope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            effectiveVideoFormatRevision: 7
        )
        sourceRoot.addChild(store.entity)
        store.synchronizeRealityKitContentTypeScope(scope)
        store.recordRealityKitContentType("equirectangular", for: scope)

        targetRoot.addChild(store.entity)
        store.synchronizeRealityKitContentTypeScope(scope)

        XCTAssertTrue(store.entity.parent === targetRoot)
        XCTAssertEqual(store.realityKitContentType, "equirectangular")
        XCTAssertEqual(store.realityKitContentTypeScope, scope)
    }

    @MainActor
    func testRealityKitContentTypeResetsForFormatAndSessionAndRejectsStaleEvents() {
        let store = PlaybackVideoEntityStore()
        let originalScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            effectiveVideoFormatRevision: 1
        )
        let overriddenFormatScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-a",
            effectiveVideoFormatRevision: 2
        )
        let replacementSessionScope = PlaybackRealityKitContentTypeScope(
            sessionID: "session-b",
            effectiveVideoFormatRevision: nil
        )

        store.synchronizeRealityKitContentTypeScope(originalScope)
        store.recordRealityKitContentType("rectilinear", for: originalScope)
        store.synchronizeRealityKitContentTypeScope(overriddenFormatScope)
        XCTAssertEqual(store.realityKitContentType, "unobserved")

        store.recordRealityKitContentType("rectilinear", for: originalScope)
        XCTAssertEqual(store.realityKitContentType, "unobserved")
        store.recordRealityKitContentType(
            "rectilinear",
            for: overriddenFormatScope
        )
        XCTAssertEqual(store.realityKitContentType, "rectilinear")

        store.synchronizeRealityKitContentTypeScope(overriddenFormatScope)
        XCTAssertEqual(
            store.realityKitContentType,
            "rectilinear",
            "Publishing final format semantics for one accepted revision must not clear its event a second time."
        )

        store.synchronizeRealityKitContentTypeScope(originalScope)
        store.synchronizeRealityKitContentTypeScope(overriddenFormatScope)
        store.recordRealityKitContentType(
            "equirectangular",
            forSessionID: "session-a"
        )
        XCTAssertEqual(
            store.realityKitContentType,
            "equirectangular",
            "A session-long subscription must attribute the event to the current accepted revision."
        )

        store.synchronizeRealityKitContentTypeScope(replacementSessionScope)
        XCTAssertEqual(store.realityKitContentType, "unobserved")
        store.recordRealityKitContentType(
            "rectilinear",
            for: overriddenFormatScope
        )
        store.recordRealityKitContentType(
            "rectilinear",
            forSessionID: "session-a"
        )
        XCTAssertEqual(store.realityKitContentType, "unobserved")
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
    func testPanoramaReturnRecoversWhenPortalModeIsNotYetReported() {
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

        guard case .requestModesAgain = first else {
            return XCTFail("A Panorama return must reapply Portal mode first.")
        }
        guard case .requestModesAgain = second else {
            return XCTFail("A missing Portal mode must keep requesting the same component mode.")
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

        guard case .requestModesAgain = firstRetry else {
            return XCTFail("A missing Portal mode must retry the existing component.")
        }
        guard case .requestModesAgain = secondRetry else {
            return XCTFail("Changing the caller's Entity must not create a renderer recovery path.")
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
    func testPanoramaRecoversWhenModesSettleButContentTypeIsInvalid() {
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

        guard case .requestModesAgain = first else {
            return XCTFail("Invalid Panorama content must first reapply the requested modes.")
        }
        guard case .requestModesAgain = second else {
            return XCTFail("Persistently invalid Panorama content must retry the existing component.")
        }
    }

    @MainActor
    func testAChangedRendererStillUsesTheStableVideoEntity() {
        let store = PlaybackVideoEntityStore()
        let first = store.entity(for: AVSampleBufferVideoRenderer())
        let second = store.entity(for: AVSampleBufferVideoRenderer())

        XCTAssertTrue(first === second)
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
    func testNewRendererRemovesThePreviousBindingAndCarriesTheNewComponentRevision() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let store = PlaybackVideoEntityStore()
        let entity = store.entity(for: renderer, videoComponentRevision: 0)
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
            videoComponentRevision: 1
        )

        XCTAssertTrue(revisedEntity === entity)
        XCTAssertNil(revisedEntity.components[VideoPlayerComponent.self])
        XCTAssertTrue(
            store.hasApplied(
                videoComponentRevision: 1,
                to: replacementRenderer
            )
        )
    }

    @MainActor
    func testRevisionAloneNeverRebindsTheSameRenderer() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let store = PlaybackVideoEntityStore()
        let entity = store.entity(for: renderer, videoComponentRevision: 0)
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )

        _ = store.entity(for: renderer, videoComponentRevision: 1)

        XCTAssertTrue(
            try XCTUnwrap(entity.components[VideoPlayerComponent.self])
                .videoRenderer === renderer
        )
        XCTAssertTrue(store.hasApplied(videoComponentRevision: 1, to: renderer))
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
    func testDockedVideoSurfaceKeepsRealityKitInputComponentsWhileContainerTemporarilyDisablesInput() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let entity = Entity()

        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: .docked,
            requestsSpatialVideoMode: false
        )

        XCTAssertNotNil(entity.components[InputTargetComponent.self])
        XCTAssertNotNil(entity.components[CollisionComponent.self])
        let accessibility = try XCTUnwrap(
            entity.components[AccessibilityComponent.self]
        )
        XCTAssertTrue(accessibility.isAccessibilityElement)
        XCTAssertNotNil(accessibility.label)
        XCTAssertTrue(accessibility.systemActions.contains(.activate))
        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .docked))

        // Presentation transitions block the containing RealityView. They do
        // not remove the entity components needed when the spatial target settles.
        XCTAssertNotNil(entity.components[InputTargetComponent.self])
        XCTAssertNotNil(entity.components[CollisionComponent.self])
        XCTAssertNotNil(entity.components[AccessibilityComponent.self])
        XCTAssertTrue(PlaybackRealityPresenter.isBound(entity, to: renderer, presentation: .docked))
    }

    @MainActor
    func testEachPresentationHasExactlyOneDirectSurfaceInputOwner() {
        XCTAssertEqual(
            PlaybackSurfaceInputOwnership.owner(for: .window),
            .windowSwiftUIRoot
        )
        XCTAssertTrue(
            PlaybackSurfaceInputOwnership.installsWindowRootTapSurface(
                for: .window
            )
        )
        XCTAssertFalse(
            PlaybackSurfaceInputOwnership.installsEntitySpatialTapGesture(
                for: .window
            )
        )

        for presentation in [PlaybackPresentation.docked, .panorama] {
            XCTAssertEqual(
                PlaybackSurfaceInputOwnership.owner(for: presentation),
                .spatialVideoEntity
            )
            XCTAssertFalse(
                PlaybackSurfaceInputOwnership.installsWindowRootTapSurface(
                    for: presentation
                )
            )
            XCTAssertTrue(
                PlaybackSurfaceInputOwnership.installsEntitySpatialTapGesture(
                    for: presentation
                )
            )
        }
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
