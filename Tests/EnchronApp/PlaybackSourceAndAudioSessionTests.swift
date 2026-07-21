import Foundation
import XCTest
@testable import Enchron

nonisolated final class PlaybackSourceAndAudioSessionTests: XCTestCase {
    func testTemporaryPhotoPlaybackFileLivesForTheSessionAndIsRemovedOnRelease() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EnchronPhotoAccessTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = directory.appending(path: "photo-source.mov")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02]).write(to: file)

        let access = PlaybackSourceAccess.temporaryFile(file)

        XCTAssertTrue(access.ensureActive())
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        access.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor
    func testAudioSessionLifecycleActivatesMoviePlaybackAndDeactivatesExactlyOnce() throws {
        let session = RecordingPlaybackAudioSession()
        let lifecycle = PlaybackAudioSessionLifecycle(session: session)

        try lifecycle.activateIfNeeded(hasAudio: true)
        try lifecycle.activateIfNeeded(hasAudio: true)
        lifecycle.deactivate()
        lifecycle.deactivate()

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

        var launchRequest: PlaybackLaunchRequest?
        let launched = expectation(description: "Media Library emitted a playback request")
        let viewModel = MediaLibraryViewModel(
            store: store,
            resolver: MediaReferenceResolver(),
            onPlay: { request in
                launchRequest = request
                launched.fulfill()
            }
        )

        viewModel.addFiles([source])
        let reference = try XCTUnwrap(viewModel.references.first)
        viewModel.play(reference)
        await fulfillment(of: [launched], timeout: 2)

        XCTAssertEqual(launchRequest?.url.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(launchRequest?.displayName, source.lastPathComponent)
        XCTAssertNil(viewModel.lastErrorMessage)
        XCTAssertEqual(try store.load().references(in: nil), [reference])
    }

    @MainActor
    func testStaleSurfaceCannotDetachItsReplacement() throws {
        let runtime = PlaybackRuntime(isUITestFixture: true)
        try runtime.attach(
            entityID: "new-surface",
            realityViewID: "new-reality-view",
            presentation: .docked
        )

        runtime.detachSurface(entityID: "old-surface", realityViewID: "old-reality-view")

        XCTAssertEqual(runtime.attachedPresentation, .docked)
        runtime.detachSurface(entityID: "new-surface", realityViewID: "new-reality-view")
        XCTAssertNil(runtime.attachedPresentation)
    }

    @MainActor
    func testOpenFailureKeepsPlayerVisibleForRetry() async throws {
        let suiteName = "app.enchron.tests.open-failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = PlaybackRuntime()
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            progressStore: PlaybackProgressStore(defaults: defaults),
            preferencesStore: UserDefaultsStore(defaults: defaults)
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
            progressStore: PlaybackProgressStore(defaults: defaults),
            preferencesStore: UserDefaultsStore(defaults: defaults)
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
    func testResumePositionIsAppliedWhenTheSessionOpens() async throws {
        let runtime = PlaybackRuntime(isUITestFixture: true)
        let request = PlaybackLaunchRequest(
            url: URL(fileURLWithPath: "/tmp/resume-test.mkv"),
            displayName: "Resume Test"
        )

        try await runtime.open(request, startTimeSeconds: 42)

        XCTAssertEqual(runtime.playbackPosition.seconds, 42)
        XCTAssertEqual(runtime.lifecycle, .ready)
        try runtime.attach(
            entityID: "resume-surface",
            realityViewID: "resume-reality-view",
            presentation: .window
        )
        XCTAssertEqual(runtime.lifecycle, .playing)
        runtime.stop()
    }

    @MainActor
    func testSpatialPresentationStaysDisabledUntilThePlaybackSurfaceIsAttached() async throws {
        let runtime = PlaybackRuntime(isUITestFixture: true)
        let request = PlaybackLaunchRequest(
            url: URL(fileURLWithPath: "/tmp/spatial-gate-test.mkv"),
            displayName: "Spatial Gate Test"
        )

        XCTAssertFalse(runtime.canEnterSpatialPresentation)
        try await runtime.open(request)
        XCTAssertFalse(runtime.canEnterSpatialPresentation)

        try runtime.attach(
            entityID: "spatial-gate-surface",
            realityViewID: "spatial-gate-reality-view",
            presentation: .window
        )
        XCTAssertTrue(runtime.canEnterSpatialPresentation)
        runtime.stop()
    }

    @MainActor
    func testRepeatedSkipAccumulatesInsteadOfReusingStalePosition() async throws {
        let runtime = PlaybackRuntime(isUITestFixture: true)
        try await runtime.open(.init(
            url: URL(fileURLWithPath: "/tmp/skip-test.mkv"),
            displayName: "Skip Test"
        ))

        runtime.skip(by: 10)
        runtime.skip(by: 10)

        XCTAssertEqual(runtime.playbackPosition.seconds, 20)
        runtime.stop()
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

    func activateForMoviePlayback() throws {
        activationCount += 1
    }

    func deactivate() throws {
        deactivationCount += 1
    }
}
