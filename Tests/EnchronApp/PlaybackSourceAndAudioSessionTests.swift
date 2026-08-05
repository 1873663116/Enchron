import Foundation
@testable import MediaLibrary
import MediaSource
import PlaybackFeature
import XCTest
@testable import Enchron

nonisolated final class PlaybackSourceAndAudioSessionTests: XCTestCase {
    @MainActor
    func testEachSurfaceTapTogglesControlsExactlyOnce() {
        let appModel = AppModel()
        let firstTap = Date(timeIntervalSinceReferenceDate: 1_000)

        appModel.toggleControlsFromPlaybackSurface(at: firstTap)
        XCTAssertFalse(appModel.showControls)

        appModel.toggleControlsFromPlaybackSurface(
            at: firstTap.addingTimeInterval(0.01)
        )
        XCTAssertTrue(appModel.showControls)
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
        XCTAssertFalse(windowModel.showControls)
        XCTAssertFalse(spatialTapModel.showControls)

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
        while session.activationCount == 0 {
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
        while session.activationCount == 0 {
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
            .fisheye
        )
        XCTAssertEqual(PlaybackRuntime.stereoLayout(from: "SideBySide"), .sideBySide)
        XCTAssertEqual(PlaybackRuntime.stereoLayout(from: "OverUnder"), .topBottom)
        XCTAssertNil(PlaybackRuntime.projectionType(from: "missing"))
        XCTAssertNil(PlaybackRuntime.stereoLayout(from: "missing"))
    }

    @MainActor
    func testWindowToPanoramaLeavesTheTargetUnclaimedUntilTheSourceVideoPlayerComponentIsRemoved() throws {
        let runtime = PlaybackRuntime()
        let sourceEntityID = "window-source"

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: sourceEntityID
        )
        runtime.releaseRendererConsumer(
            presentation: .window,
            entityID: sourceEntityID,
            retainingCurrentRendererGraphFor: .panorama
        )

        XCTAssertThrowsError(
            try runtime.claimRendererConsumer(
                presentation: .panorama,
                entityID: "panorama-target"
            )
        ) { error in
            guard case .rendererTransferPending = error as? PlaybackRuntime.RuntimeError else {
                return XCTFail("Expected the target renderer claim to remain pending, got \(error)")
            }
        }
        XCTAssertNil(runtime.rendererConsumerPresentation)
        XCTAssertNil(runtime.rendererConsumerEntityID)
    }

    @MainActor
    func testWindowToPanoramaDoesNotLetAnotherPresentationClaimThePendingTargetGraph() throws {
        let runtime = PlaybackRuntime()
        let sourceEntityID = "window-source"

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: sourceEntityID
        )
        runtime.releaseRendererConsumer(
            presentation: .window,
            entityID: sourceEntityID,
            retainingCurrentRendererGraphFor: .panorama
        )

        XCTAssertThrowsError(
            try runtime.claimRendererConsumer(
                presentation: .docked,
                entityID: "third-presentation"
            )
        ) { error in
            guard case .rendererTransferPending = error as? PlaybackRuntime.RuntimeError else {
                return XCTFail("Expected the pending Panorama graph to reject a third presentation, got \(error)")
            }
        }
        XCTAssertEqual(runtime.videoComponentRevision, 0)
        XCTAssertNil(runtime.rendererConsumerPresentation)
    }

    @MainActor
    func testOnlyWindowToPanoramaMayTransferTheCurrentRendererGraphToAnotherEntity() throws {
        let runtime = PlaybackRuntime()

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "window-source"
        )
        runtime.releaseRendererConsumer(
            presentation: .window,
            entityID: "window-source",
            retainingCurrentRendererGraphFor: .docked
        )

        XCTAssertThrowsError(
            try runtime.claimRendererConsumer(
                presentation: .docked,
                entityID: "docked-target"
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
    private var activationContinuation: CheckedContinuation<Void, any Error>?

    func activateForMoviePlayback() async throws {
        activationCount += 1
        try await withCheckedThrowingContinuation { continuation in
            activationContinuation = continuation
        }
    }

    func deactivate() async throws {
        deactivationCount += 1
    }

    func finishActivation() {
        activationContinuation?.resume()
        activationContinuation = nil
    }
}
