import AVFoundation
import CoreMedia
import PlaybackCore
import RealityKit
import XCTest
@testable import EnchronMacOS

nonisolated final class MacRealityPlaybackContractTests: XCTestCase {
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
                verticalOffset: 0.25,
                depthOffset: -0.5,
                viewAngle: 12,
                scale: 1.3
            )
        )

        XCTAssertEqual(ObjectIdentifier(videoEntity), identity)
        XCTAssertTrue(videoEntity.parent === anchor)
        XCTAssertEqual(videoEntity.position.x, 0, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.position.y, 0.25, accuracy: 0.0001)
        XCTAssertEqual(videoEntity.position.z, -0.5, accuracy: 0.0001)
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
                verticalOffset: 0,
                depthOffset: 0,
                viewAngle: 0,
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
    func testSubtitleTextComponentFollowsTheSharedVideoEntityIntoDockedScene() throws {
        let videoEntity = Entity()
        let subtitleEntity = Entity()
        let anchor = Entity()
        let cue = PlaybackSubtitleCue(
            id: "cue-1",
            trackID: "subtitle-1",
            timeRange: CMTimeRange(
                start: CMTime(seconds: 1, preferredTimescale: 600),
                duration: CMTime(seconds: 2, preferredTimescale: 600)
            ),
            text: "第一行\nSecond line"
        )

        PlaybackSubtitlePresenter.update(
            subtitleEntity,
            on: videoEntity,
            presentation: .window,
            screenSize: [16.0 / 9.0, 1],
            cues: [cue]
        )

        let component = try XCTUnwrap(subtitleEntity.components[TextComponent.self])
        let renderedText = component.text.map { String($0.characters) } ?? ""
        XCTAssertTrue(subtitleEntity.parent === videoEntity)
        XCTAssertTrue(subtitleEntity.isEnabled)
        XCTAssertTrue(renderedText.contains("第一行"))

        PlaybackSurfacePlacement.dock(
            videoEntity,
            to: anchor,
            transform: .init(
                verticalOffset: 0,
                depthOffset: 0,
                viewAngle: 0,
                scale: 1.3
            )
        )

        XCTAssertTrue(videoEntity.parent === anchor)
        XCTAssertTrue(subtitleEntity.parent === videoEntity)
        XCTAssertNotNil(subtitleEntity.components[TextComponent.self])
    }
}
