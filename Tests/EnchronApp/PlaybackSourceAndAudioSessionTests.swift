import Foundation
@testable import MediaLibrary
import MediaSource
import PlaybackCore
import PlaybackFeature
import XCTest
@testable import Enchron

nonisolated final class PlaybackSourceAndAudioSessionTests: XCTestCase {
    @MainActor
    func testEffectiveFormatPresentationResolutionUsesTheSameInterpretationForSourceAndOverride() {
        let panoramicSource = MediaFormatInterpretationResolver.resolve(
            source: SourceMediaFormatFact(
                contentKind: .halfEquirectangular,
                projection: .equirectangular180,
                stereoLayout: .mono
            ),
            override: nil
        )
        XCTAssertEqual(
            EffectiveMediaFormatPresentationResolver.resolve(
                panoramicSource,
                from: .window
            ),
            .enterPanorama
        )

        let flatOverride = MediaFormatInterpretationResolver.resolve(
            source: panoramicSource.source,
            override: .standard
        )
        XCTAssertEqual(
            EffectiveMediaFormatPresentationResolver.resolve(
                flatOverride,
                from: .panorama
            ),
            .returnToWindow
        )
    }

    @MainActor
    func testVideoFormatEditorDefaultsToFlatMonoAndAutomaticDiscardsItsDraft() {
        var state = PlaybackTopActionsState()
        XCTAssertEqual(state.projection, .flat)
        XCTAssertEqual(state.stereoLayout, .mono)

        state.toggleMenu(.videoFormat)
        state.projection = .equirectangular360
        state.stereoLayout = .sideBySide

        XCTAssertTrue(state.restoreAutomaticFormat())
        XCTAssertNil(state.presentedMenu)
        XCTAssertEqual(state.projection, .flat)
        XCTAssertEqual(state.stereoLayout, .mono)
    }

    @MainActor
    func testEachSurfaceTapTogglesControlsExactlyOnce() {
        let appModel = AppModel()
        let firstTap = Date(timeIntervalSinceReferenceDate: 1_000)

        appModel.toggleControlsFromPlaybackSurface(at: firstTap)
        XCTAssertTrue(appModel.showControls)

        appModel.toggleControlsFromPlaybackSurface(
            at: firstTap.addingTimeInterval(0.01)
        )
        XCTAssertFalse(appModel.showControls)
    }

    @MainActor
    func testEverySurfaceInputSourceUsesTheSameStableToggleAction() {
        let windowModel = AppModel()
        let spatialTapModel = AppModel()
        let accessibilityModel = AppModel()
        let moment = Date(timeIntervalSinceReferenceDate: 2_000)

        PlaybackSurfaceInputAction.perform(
            .windowSwiftUI,
            appModel: windowModel,
            at: moment
        )
        PlaybackSurfaceInputAction.perform(
            .spatialTap,
            appModel: spatialTapModel,
            at: moment
        )
        PlaybackSurfaceInputAction.perform(
            .accessibilityActivate,
            appModel: accessibilityModel,
            at: moment
        )

        XCTAssertEqual(windowModel.showControls, spatialTapModel.showControls)
        XCTAssertEqual(spatialTapModel.showControls, accessibilityModel.showControls)
        XCTAssertTrue(windowModel.showControls)
        XCTAssertTrue(spatialTapModel.showControls)

    }

    func testTemporaryPhotoPlaybackFileLivesForTheSessionAndIsRemovedOnRelease() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EnchronPhotoAccessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = directory.appending(path: "photo-source.mov")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: file)

        let access = MediaAccessLease.temporaryFile(file)

        XCTAssertTrue(access.ensureActive())
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        access.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testAudioSessionLifecycleActivatesMoviePlaybackAndDeactivatesExactlyOnce() async throws {
        let session = RecordingPlaybackAudioSession()
        let lifecycle = PlaybackAudioSessionLifecycle(session: session)

        try await lifecycle.activateIfNeeded(hasAudio: true)
        try await lifecycle.activateIfNeeded(hasAudio: true)
        await lifecycle.deactivate()
        await lifecycle.deactivate()

        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertFalse(lifecycle.isActive)
    }

    @MainActor
    func testAudioSessionLifecycleCanReactivateAfterEndedDeactivation() async throws {
        let session = RecordingPlaybackAudioSession()
        let lifecycle = PlaybackAudioSessionLifecycle(session: session)

        try await lifecycle.activateIfNeeded(hasAudio: true)
        await lifecycle.deactivate()
        try await lifecycle.activateIfNeeded(hasAudio: true)

        XCTAssertEqual(session.activationCount, 2)
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertTrue(lifecycle.isActive)
    }

    @MainActor
    func testConcurrentActivationRequestsShareOneSystemActivation() async throws {
        let session = SuspendedPlaybackAudioSession()
        let lifecycle = PlaybackAudioSessionLifecycle(session: session)

        let first = Task { @MainActor in
            try await lifecycle.activateIfNeeded(hasAudio: true)
        }
        while session.isActivationSuspended == false {
            await Task.yield()
        }
        let second = Task { @MainActor in
            try await lifecycle.activateIfNeeded(hasAudio: true)
        }
        await Task.yield()
        session.finishActivation()

        try await first.value
        try await second.value
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertTrue(lifecycle.isActive)
    }

    @MainActor
    func testDeactivationWaitsForPendingActivation() async throws {
        let session = SuspendedPlaybackAudioSession()
        let lifecycle = PlaybackAudioSessionLifecycle(session: session)

        let activation = Task { @MainActor in
            try await lifecycle.activateIfNeeded(hasAudio: true)
        }
        while session.isActivationSuspended == false {
            await Task.yield()
        }
        let deactivation = Task { @MainActor in
            await lifecycle.deactivate()
        }
        await Task.yield()
        XCTAssertEqual(session.deactivationCount, 0)
        session.finishActivation()

        try await activation.value
        await deactivation.value
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertFalse(lifecycle.isActive)
    }

    @MainActor
    func testFileAddedToMediaLibraryResolvesToTheOriginalPlaybackSource() async throws {
        let suiteName = "app.enchron.tests.media-reference.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMediaLibraryStore(defaults: defaults)
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let source = root.appending(path: "original.mp4")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        var playbackItem: MediaPlaybackItem?
        let launched = expectation(description: "Media Library emitted a playback request")
        let viewModel = MediaLibraryViewModel(
            store: store,
            resolver: MediaReferenceResolver(),
            onPlay: { item in
                playbackItem = item
                launched.fulfill()
            }
        )

        viewModel.addFiles([source])
        let reference = try XCTUnwrap(viewModel.references.first)
        viewModel.play(reference)
        await fulfillment(of: [launched], timeout: 2)

        XCTAssertEqual(playbackItem?.url.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(playbackItem?.displayName, source.lastPathComponent)
        XCTAssertNil(viewModel.lastErrorMessage)
        XCTAssertEqual(try store.load().references(in: nil), [reference])
    }

    @MainActor
    func testOpenFailureKeepsPlayerVisibleForRetry() async throws {
        let suiteName = "app.enchron.tests.open-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = PlaybackRuntime()
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            preferencesProvider: UserDefaultsStore(defaults: defaults)
        )
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).mkv")

        launcher.beginPlayback(.init(url: missingURL, displayName: "Missing Video"))

        let deadline = ContinuousClock.now + .seconds(5)
        while runtime.lastErrorMessage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        guard case .failed = runtime.lifecycle else {
            return XCTFail("Expected PlaybackCore to publish a failed lifecycle, got \(runtime.lifecycle)")
        }
        XCTAssertNotNil(runtime.lastErrorMessage)
        XCTAssertTrue(runtime.hasActivePlaybackRequest)
        XCTAssertEqual(runtime.currentLaunchRequest?.displayName, "Missing Video")
        launcher.stopPlayback()
    }

    @MainActor
    func testWaitingForStopAfterOpenFailureClearsThePlaybackProjection() async throws {
        let suiteName = "app.enchron.tests.waiting-stop.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = PlaybackRuntime()
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            preferencesProvider: UserDefaultsStore(defaults: defaults)
        )
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).mkv")

        launcher.beginPlayback(.init(url: missingURL, displayName: "Missing Video"))

        let deadline = ContinuousClock.now + .seconds(5)
        while runtime.lastErrorMessage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        guard case .failed = runtime.lifecycle else {
            return XCTFail("Expected PlaybackCore to publish a failed lifecycle, got \(runtime.lifecycle)")
        }
        XCTAssertTrue(runtime.hasActivePlaybackRequest)

        await launcher.stopPlaybackAndWait()

        XCTAssertFalse(runtime.hasActivePlaybackRequest)
        XCTAssertNil(runtime.currentLaunchRequest)
        XCTAssertNil(runtime.activeSessionID)
        XCTAssertNil(runtime.renderer)
        XCTAssertNil(runtime.attachedPresentation)
        XCTAssertNil(runtime.rendererConsumerPresentation)
        XCTAssertNil(runtime.rendererConsumerEntityID)
        XCTAssertEqual(runtime.lifecycle, .idle)
    }

    @MainActor
    func testAppleImmersiveVideoFailsBeforePublishingAudioOrVideoPlayback() async throws {
        let testMedia = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestMedia")
        let fixture = testMedia.appendingPathComponent(
            "Samples/Spatial/Apple-Immersive/Apple-Streaming-Examples/Immersive-Video-example.f99766.mp4"
        )
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Apple Immersive Video fixture is not available in this test process.")
        }
        let runtime = PlaybackRuntime()
        let request = PlaybackLaunchRequest(
            url: fixture,
            displayName: fixture.lastPathComponent
        )

        do {
            try await runtime.open(request)
            XCTFail("Apple Immersive Video must fail before renderer publication.")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Unable to open this file.")
        }

        XCTAssertNil(runtime.activeSessionID)
        XCTAssertNil(runtime.renderer)
        XCTAssertTrue(runtime.availableAudioTracks.isEmpty)
        XCTAssertEqual(runtime.lastErrorMessage, "Unable to open this file.")
    }

    @MainActor
    func testPlaybackCoreDimensionSeparatorsProduceTheSameResolution() {
        let ascii = PlaybackRuntime.parseResolution("3840x2160")
        let typographic = PlaybackRuntime.parseResolution("3840×2160")

        XCTAssertEqual(ascii, .init(width: 3840, height: 2160))
        XCTAssertEqual(typographic, ascii)
        XCTAssertNil(PlaybackRuntime.parseResolution("unknown"))
    }

    @MainActor
    func testPlaybackCoreSpatialFormatFactsMapToProductProfile() {
        XCTAssertEqual(
            PlaybackRuntime.projectionType(from: "HalfEquirectangular"),
            .equirectangular180
        )
        XCTAssertEqual(
            PlaybackRuntime.projectionType(from: "Equirectangular"),
            .equirectangular360
        )
        XCTAssertEqual(
            PlaybackRuntime.projectionType(from: "AppleImmersiveVideo"),
            .flat
        )
        XCTAssertEqual(
            PlaybackRuntime.sourceVideoContentKind(
                from: "AppleImmersiveVideo",
                isMVHEVC: true
            ),
            .appleImmersiveVideo
        )
        XCTAssertEqual(
            PlaybackRuntime.sourceVideoContentKind(
                from: "ParametricImmersive",
                isMVHEVC: false
            ),
            .parametricImmersive
        )
        XCTAssertEqual(
            PlaybackRuntime.sourceVideoContentKind(from: "missing", isMVHEVC: true),
            .spatialVideo
        )
        XCTAssertEqual(PlaybackRuntime.stereoLayout(from: "SideBySide"), .sideBySide)
        XCTAssertEqual(PlaybackRuntime.stereoLayout(from: "OverUnder"), .topBottom)
        XCTAssertEqual(
            PlaybackRuntime.stereoLayout(from: "missing", isMVHEVC: true),
            .multiview
        )
        XCTAssertNil(PlaybackRuntime.projectionType(from: "missing"))
        XCTAssertNil(PlaybackRuntime.stereoLayout(from: "missing"))
    }

    @MainActor
    func testEffectiveHorizontalCoverageMatchesTheSelectedProjection() {
        XCTAssertEqual(
            PlaybackRuntime.effectiveHorizontalFieldOfViewDegrees(
                for: .equirectangular180,
                explicitDegrees: nil
            ),
            180
        )
        XCTAssertEqual(
            PlaybackRuntime.effectiveHorizontalFieldOfViewDegrees(
                for: .equirectangular360,
                explicitDegrees: nil
            ),
            360
        )
        XCTAssertEqual(
            PlaybackRuntime.effectiveHorizontalFieldOfViewDegrees(
                for: .customAngle,
                explicitDegrees: 230
            ),
            230
        )
    }

    @MainActor
    func testAcceptedCoreFormatRevisionIsObservableSessionIdentityOnly() {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(
            controller: controller,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
        let request = PlaybackLaunchRequest(
            url: URL(fileURLWithPath: "/tmp/format-revision.mp4"),
            displayName: "format-revision.mp4"
        )
        runtime.prepareForPlayback(request)
        XCTAssertNil(runtime.effectiveVideoFormatRevision)

        controller.onAcceptedVideoFormatRevisionChange?(7)

        XCTAssertEqual(runtime.effectiveVideoFormatRevision, 7)
        controller.onAcceptedVideoFormatRevisionChange?(8)
        XCTAssertEqual(runtime.effectiveVideoFormatRevision, 8)
        controller.onAcceptedVideoFormatRevisionChange?(7)
        XCTAssertEqual(
            runtime.effectiveVideoFormatRevision,
            8,
            "An out-of-order accepted-input callback must not move a session back to an older format."
        )
        XCTAssertEqual(runtime.videoComponentRevision, 0)

        runtime.prepareForPlayback(request)
        XCTAssertNil(runtime.effectiveVideoFormatRevision)
    }

    @MainActor
    func testWindowToPanoramaTransfersTheSameEntityWithoutReplacingItsGraph() throws {
        let runtime = PlaybackRuntime()
        let entityID = "stable-video-entity"

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: entityID
        )
        runtime.releaseRendererConsumer(
            presentation: .window,
            entityID: entityID,
            preservingVideoComponent: true
        )

        try runtime.claimRendererConsumer(
            presentation: .panorama,
            entityID: entityID
        )

        XCTAssertEqual(runtime.rendererConsumerPresentation, .panorama)
        XCTAssertEqual(runtime.rendererConsumerEntityID, entityID)
        XCTAssertEqual(runtime.videoComponentRevision, 0)
    }

    @MainActor
    func testCrossRealityViewTransferAcceptsANewEntityAfterSourceRelease() throws {
        let runtime = PlaybackRuntime()
        let sourceEntityID = "window-source"

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: sourceEntityID
        )
        runtime.releaseRendererConsumer(
            presentation: .window,
            entityID: sourceEntityID,
            preservingVideoComponent: true
        )

        try runtime.claimRendererConsumer(
            presentation: .docked,
            entityID: "immersive-target"
        )

        XCTAssertEqual(runtime.videoComponentRevision, 0)
        XCTAssertEqual(runtime.rendererConsumerPresentation, .docked)
        XCTAssertEqual(runtime.rendererConsumerEntityID, "immersive-target")
    }

    @MainActor
    func testTransferWithinOneRealityViewOwnershipRejectsANewEntity() throws {
        let runtime = PlaybackRuntime()

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "window-source"
        )
        runtime.releaseRendererConsumer(
            presentation: .window,
            entityID: "window-source",
            preservingVideoComponent: true
        )

        XCTAssertThrowsError(
            try runtime.claimRendererConsumer(
                presentation: .portal,
                entityID: "portal-target"
            )
        ) { error in
            guard case .rendererTransferPending = error as? PlaybackRuntime.RuntimeError else {
                return XCTFail("Expected a pending renderer transfer, got \(error)")
            }
        }
    }

    @MainActor
    func testControlsAutoHideCountdownRestartsAfterHoverEnds() {
        let appModel = AppModel()
        let entered = Date(timeIntervalSince1970: 100)
        let exited = Date(timeIntervalSince1970: 105)

        appModel.setControlsFocused(true, at: entered)
        appModel.setControlsFocused(false, at: exited)

        XCTAssertFalse(appModel.isControlsFocused)
        XCTAssertEqual(appModel.lastControlsInteractionAt, exited)
    }

}

@MainActor
private final class RecordingPlaybackAudioSession: PlaybackAudioSessionManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    func activateForMoviePlayback() async throws {
        activationCount += 1
    }

    func deactivate() async throws {
        deactivationCount += 1
    }
}

@MainActor
private final class SuspendedPlaybackAudioSession: PlaybackAudioSessionManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    private(set) var isActivationSuspended = false
    private var activationContinuation: CheckedContinuation<Void, any Error>?

    func activateForMoviePlayback() async throws {
        activationCount += 1
        try await withCheckedThrowingContinuation { continuation in
            activationContinuation = continuation
            isActivationSuspended = true
        }
    }

    func deactivate() async throws {
        deactivationCount += 1
    }

    func finishActivation() {
        activationContinuation?.resume()
        activationContinuation = nil
        isActivationSuspended = false
    }
}
