import AVFoundation
import CoreMedia
import PlaybackCore
import PlaybackPresentation
import RealityKit
import XCTest
@testable import EnchronMacOS

nonisolated final class MacRealityPlaybackContractTests: XCTestCase {
    @MainActor
    func testPlaybackSurfaceMountPolicyFollowsVisiblePlaybackLifecycle() {
        XCTAssertFalse(
            PlaybackSurfaceMountPolicy.shouldMount(showsWindowPlayback: false)
        )
        XCTAssertTrue(
            PlaybackSurfaceMountPolicy.shouldMount(showsWindowPlayback: true)
        )
    }

    @MainActor
    func testMacPresentationHostMakesPanoramaAnExplicitWindowSimulation() {
        XCTAssertEqual(
            MacPlaybackPresentationHost.surfacePresentation(for: .window),
            .window
        )
        XCTAssertEqual(
            MacPlaybackPresentationHost.surfacePresentation(for: .docked),
            .docked
        )
        XCTAssertEqual(
            MacPlaybackPresentationHost.surfacePresentation(for: .panorama),
            .window
        )
        XCTAssertEqual(
            MacPlaybackPresentationHost.simulatedPresentation(
                productPresentation: .panorama,
                surfacePresentation: .window
            ),
            .panorama
        )
        XCTAssertNil(
            MacPlaybackPresentationHost.simulatedPresentation(
                productPresentation: .window,
                surfacePresentation: .window
            )
        )
    }

    @MainActor
    func testWindowAndDockedPlacementReparentsTheSameVideoEntity() {
        let windowRoot = Entity()
        let anchor = Entity()
        let videoEntity = Entity()
        let identity = ObjectIdentifier(videoEntity)
        windowRoot.addChild(anchor)
        windowRoot.addChild(videoEntity)

        PlaybackSurfacePlacement.window(videoEntity)
        XCTAssertTrue(videoEntity.parent === windowRoot)
        XCTAssertEqual(videoEntity.position, .zero)
        XCTAssertEqual(videoEntity.scale, .one)

        PlaybackSurfacePlacement.dock(
            videoEntity,
            to: anchor,
            transform: .init(
                distance: 0.5,
                elevationDegrees: 30,
                scale: 1.3
            )
        )

        XCTAssertEqual(ObjectIdentifier(videoEntity), identity)
        XCTAssertTrue(videoEntity.parent === anchor)
        XCTAssertEqual(videoEntity.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.position.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.position.z, -0.433_012_7, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.scale.x, 1.3, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.scale.y, 1.3, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.scale.z, 1.3, accuracy: 0.0001)

        windowRoot.addChild(videoEntity)
        PlaybackSurfacePlacement.window(videoEntity)

        XCTAssertEqual(ObjectIdentifier(videoEntity), identity)
        XCTAssertTrue(videoEntity.parent === windowRoot)
        XCTAssertEqual(videoEntity.position, .zero)
        XCTAssertEqual(videoEntity.scale, .one)
    }

    @MainActor
    func testWindowCameraFitsLandscapeVideoToCanvas() {
        let geometry = MacWindowPlaybackCameraGeometry.resolve(
            screenSize: [16.0 / 9.0, 1],
            canvasSize: CGSize(width: 1280, height: 720)
        )
        let visibleHeight = 2 * geometry.distance
            * tan(MacWindowPlaybackCameraGeometry.fieldOfViewInDegrees * .pi / 360)

        XCTAssertEqual(
            geometry.screenSize.y / visibleHeight,
            MacWindowPlaybackCameraGeometry.fillFraction,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testWindowCameraFitsWideVideoByHorizontalDimension() {
        let geometry = MacWindowPlaybackCameraGeometry.resolve(
            screenSize: [2.4, 1],
            canvasSize: CGSize(width: 1024, height: 768)
        )
        let visibleHeight = 2 * geometry.distance
            * tan(MacWindowPlaybackCameraGeometry.fieldOfViewInDegrees * .pi / 360)
        let visibleWidth = visibleHeight * Float(1024.0 / 768.0)

        XCTAssertEqual(
            geometry.screenSize.x / visibleWidth,
            MacWindowPlaybackCameraGeometry.fillFraction,
            accuracy: 0.0001
        )
    }

    @MainActor
    func testProductRCPWorldLoadsWithCanonicalPlaybackSurfaceAnchor() async throws {
        let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
        let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)

        XCTAssertEqual(anchor.name, PlaybackSurfaceAnchorResolver.canonicalName)
        XCTAssertTrue(world.findEntity(named: PlaybackSurfaceAnchorResolver.canonicalName) === anchor)
        XCTAssertNil(anchor.components[ModelComponent.self])
        XCTAssertTrue(anchor.children.allSatisfy { $0.components[ModelComponent.self] == nil })
    }

    @MainActor
    func testWindowToDockedConfigurationReusesOneVideoPlayerComponentConsumer() throws {
        let renderer = AVSampleBufferVideoRenderer()
        let videoEntity = Entity()
        let anchor = Entity()

        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: .window,
            stereoLayout: .mono
        )
        let windowComponent = try XCTUnwrap(
            videoEntity.components[VideoPlayerComponent.self]
        )
        XCTAssertTrue(windowComponent.videoRenderer === renderer)

        PlaybackSurfacePlacement.dock(
            videoEntity,
            to: anchor,
            transform: .init(
                distance: 2,
                elevationDegrees: 0,
                scale: 1.3
            )
        )
        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: .docked,
            stereoLayout: .sideBySide
        )

        let dockedComponent = try XCTUnwrap(
            videoEntity.components[VideoPlayerComponent.self]
        )
        XCTAssertTrue(dockedComponent.videoRenderer === windowComponent.videoRenderer)
        XCTAssertTrue(dockedComponent.videoRenderer === renderer)
        XCTAssertTrue(
            PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: .docked
            )
        )
        XCTAssertTrue(videoEntity.parent === anchor)
        XCTAssertNil(videoEntity.components[ModelComponent.self])
        XCTAssertEqual(dockedComponent.desiredViewingMode, .mono)
    }

    @MainActor
    func testPausedPresentationCanCommitAfterTheRendererSurfaceAttaches() {
        let record = PresentationStateRecord(
            mediaSessionID: "session",
            requestedMode: PlaybackPresentation.docked.rawValue,
            phase: "surfaceAttached",
            platform: "macOS"
        )

        XCTAssertTrue(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: record,
                presentation: .docked,
                activeSessionID: "session",
                lifecycle: .paused
            )
        )
        XCTAssertFalse(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: record,
                presentation: .docked,
                activeSessionID: "session",
                lifecycle: .playing
            )
        )
    }

    @MainActor
    func testPanoramaRequiresObservedVideoPlayerModesBeforeCommit() {
        let attached = PresentationStateRecord(
            mediaSessionID: "session",
            requestedMode: PlaybackPresentation.panorama.rawValue,
            phase: "surfaceAttached",
            platform: "visionOS"
        )
        let settled = PresentationStateRecord(
            mediaSessionID: "session",
            requestedMode: PlaybackPresentation.panorama.rawValue,
            phase: "settled",
            platform: "visionOS"
        )

        XCTAssertFalse(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: attached,
                presentation: .panorama,
                activeSessionID: "session",
                lifecycle: .paused
            )
        )
        XCTAssertTrue(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: settled,
                presentation: .panorama,
                activeSessionID: "session",
                lifecycle: .paused
            )
        )
    }

    @MainActor
    func testPresentationCommitRejectsTheWrongSessionAndTarget() {
        let record = PresentationStateRecord(
            mediaSessionID: "stale-session",
            requestedMode: PlaybackPresentation.window.rawValue,
            phase: "settled",
            platform: "macOS"
        )

        XCTAssertFalse(
            PlaybackRuntime.presentationTransitionCanCommit(
                record: record,
                presentation: .docked,
                activeSessionID: "current-session",
                lifecycle: .paused
            )
        )
    }

    @MainActor
    func testSubtitleGPUFrameFollowsTheSharedVideoEntityAndRelayoutsForControls() throws {
        let videoEntity = Entity()
        let surface = PlaybackSubtitleSurface()
        let anchor = Entity()
        let frame = PlaybackSubtitleFrame(
            kind: .libass,
            canvasWidth: 1_920,
            canvasHeight: 1_080,
            contentX: 639,
            contentY: 904,
            contentWidth: 658,
            contentHeight: 132,
            bytesPerRow: 2_632,
            premultipliedBGRA: Data(repeating: 255, count: 347_424),
            changeIdentifier: 1
        )

        surface.update(
            on: videoEntity,
            presentation: .window,
            screenSize: [16.0 / 9.0, 1],
            reservedBottomFraction: 0.32,
            frame: frame
        )

        XCTAssertTrue(surface.entity.parent === videoEntity)
        XCTAssertTrue(surface.entity.isEnabled)
        XCTAssertNotNil(surface.entity.components[ModelComponent.self])
        let elevatedY = surface.entity.position.y

        surface.update(
            on: videoEntity,
            presentation: .window,
            screenSize: [16.0 / 9.0, 1],
            reservedBottomFraction: 0,
            frame: frame
        )
        XCTAssertLessThan(surface.entity.position.y, elevatedY)

        PlaybackSurfacePlacement.dock(
            videoEntity,
            to: anchor,
            transform: .init(
                distance: 2,
                elevationDegrees: 0,
                scale: 1.3
            )
        )

        XCTAssertTrue(videoEntity.parent === anchor)
        XCTAssertTrue(surface.entity.parent === videoEntity)
        XCTAssertNotNil(surface.entity.components[ModelComponent.self])
    }
}
