import CoreMedia
import Foundation
@testable import Emby
@testable import MediaLibrary
import MediaSource
import PlaybackCore
@_spi(Testing) @testable import Playback
import RealityKit
import SwiftUI
import UIKit
import XCTest
@testable import Enchron

nonisolated final class PlaybackSourceAndAudioSessionTests: XCTestCase {
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
        let appModel = PlaybackSessionModel()
        let firstTap = Date(timeIntervalSinceReferenceDate: 1_000)

        appModel.toggleControlsFromPlaybackSurface(at: firstTap)
        XCTAssertTrue(appModel.showControls)

        appModel.toggleControlsFromPlaybackSurface(
            at: firstTap.addingTimeInterval(0.01)
        )
        XCTAssertFalse(appModel.showControls)
    }

    @MainActor
    func testTheFirstSurfaceTapAfterASecondaryMenuOnlyClosesTheMenu() {
        let appModel = PlaybackSessionModel()
        let moment = Date(timeIntervalSinceReferenceDate: 3_000)
        appModel.toggleControlsFromPlaybackSurface(at: moment)
        appModel.setWindowSecondaryMenuPresented(true)
        appModel.setControlsFocused(true, at: moment)

        appModel.toggleControlsFromPlaybackSurface(at: moment.addingTimeInterval(1))
        XCTAssertTrue(appModel.showControls)
        XCTAssertFalse(appModel.windowSecondaryMenuIsPresented)
        XCTAssertFalse(appModel.isControlsFocused)

        appModel.toggleControlsFromPlaybackSurface(at: moment.addingTimeInterval(2))
        XCTAssertFalse(appModel.showControls)
    }

    @MainActor
    func testEverySurfaceInputSourceUsesTheSameStableToggleAction() {
        let windowModel = PlaybackSessionModel()
        let spatialTapModel = PlaybackSessionModel()
        let accessibilityModel = PlaybackSessionModel()
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
        while runtime.userVisibleIssue == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        guard case .failed = runtime.lifecycle else {
            return XCTFail("Expected PlaybackCore to publish a failed lifecycle, got \(runtime.lifecycle)")
        }
        XCTAssertEqual(runtime.userVisibleIssue, .mediaOpeningFailed)
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
        while runtime.userVisibleIssue == nil, ContinuousClock.now < deadline {
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
    func testAppleImmersiveVideoOpensWithItsExactSourcePresentationFacts() async throws {
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
        defer { runtime.stop() }
        let request = PlaybackLaunchRequest(
            url: fixture,
            displayName: fixture.lastPathComponent
        )

        try await runtime.open(request)

        XCTAssertNotNil(runtime.activeSessionID)
        XCTAssertNotNil(runtime.renderer)
        XCTAssertNil(runtime.userVisibleIssue)
        XCTAssertEqual(runtime.activeMediaFormatProvenance, .source)
        XCTAssertEqual(runtime.sourceVideoContentKind, .appleImmersiveVideo)
        XCTAssertEqual(runtime.effectiveProjectionType, .flat)
        XCTAssertEqual(runtime.effectiveStereoLayout, .multiview)
        XCTAssertTrue(runtime.effectiveContentIsPanoramic)
        XCTAssertTrue(runtime.diagnostics.isMVHEVC)
        let snapshot = try XCTUnwrap(runtime.debugSnapshot())
        XCTAssertEqual(
            snapshot.providerOpen?.formatSignaling.projectionKind.value,
            "AppleImmersiveVideo"
        )
        XCTAssertEqual(snapshot.providerOpen?.formatSignaling.lhvC.value, true)
        XCTAssertEqual(
            snapshot.providerOpen?.codecConfigurationSummary.value,
            "hvcC,lhvC"
        )

        await runtime.stopAndWait()
        XCTAssertNil(runtime.activeSessionID)
        XCTAssertNil(runtime.renderer)
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
    func testTechnicalSessionReplacementUsesTheFinalCutoverPositionAndPreservesSelections()
        async throws {
        let fixture = URL(
            fileURLWithPath:
                "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv"
        )
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("The multi-track playback fixture is not available in this test process.")
        }
        let runtime = PlaybackRuntime()
        addTeardownBlock { @MainActor in
            await runtime.stopAndWait()
        }
        try await runtime.open(
            PlaybackLaunchRequest(
                url: fixture,
                displayName: fixture.lastPathComponent
            )
        )
        let logicalSessionID = try XCTUnwrap(runtime.activeSessionID)
        let sourceTechnicalSessionID = try XCTUnwrap(runtime.activeTechnicalSessionID)
        let selectedAudioTrack = try XCTUnwrap(
            runtime.availableAudioTracks.first {
                $0.id != runtime.currentAudioTrackID
            }
        )
        let selectedSubtitleTrack = try XCTUnwrap(runtime.availableSubtitleTracks.first)
        try await runtime.selectAudioTrack(selectedAudioTrack)
        try await runtime.selectSubtitleTrack(selectedSubtitleTrack)

        let sourceEntity = Entity()
        PlaybackRealityPresenter.configure(
            sourceEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        let sourceViewHost = try PlaybackRealityViewTestHost(entity: sourceEntity)
        defer { sourceViewHost.close() }
        try await sourceViewHost.waitUntilReady()
        try runtime.attach(
            entityID: "source-video-entity",
            realityViewID: "source-reality-view",
            presentation: .window
        )
        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "source-video-entity"
        )
        let sourceVideoComponentRevision = runtime.videoComponentRevision
        runtime.videoRendererTargetDidBind(
            revision: sourceVideoComponentRevision,
            entityID: "source-video-entity"
        )
        try await runtime.beginPlaybackForPresentationSettlement(
            mediaSessionID: logicalSessionID
        )
        let sourceSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let sourcePositionBeforePreparation = try await waitUntilPlaybackAdvances(
            runtime,
            sourceSession,
            beyond: .zero
        )
        XCTAssertEqual(runtime.productLifecycle, .playing)

        try await runtime.prepareTechnicalSessionForPresentationConversion()

        let sourcePositionAfterPreparation = sourceSession.currentTime()
        XCTAssertGreaterThan(
            CMTimeCompare(sourcePositionAfterPreparation, sourcePositionBeforePreparation),
            0
        )
        try await runtime.activatePreparedTechnicalSessionReplacement()

        let firstReplacementSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let firstCutoverPosition = sourceSession.currentTime()
        XCTAssertEqual(runtime.activeSessionID, logicalSessionID)
        XCTAssertNotEqual(runtime.activeTechnicalSessionID, sourceTechnicalSessionID)
        XCTAssertEqual(runtime.currentAudioTrackID, selectedAudioTrack.id)
        XCTAssertEqual(runtime.currentSubtitleTrackID, selectedSubtitleTrack.id)
        XCTAssertNotEqual(runtime.productLifecycle, .playing)
        XCTAssertEqual(runtime.technicalSessionReplacementStage, .installingRenderer)

        let firstTargetEntity = Entity()
        PlaybackRealityPresenter.configure(
            firstTargetEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .docked,
            requestsSpatialVideoMode: false
        )
        let firstTargetViewHost = try PlaybackRealityViewTestHost(entity: firstTargetEntity)
        defer { firstTargetViewHost.close() }
        try await firstTargetViewHost.waitUntilReady()
        try runtime.claimRendererConsumer(
            presentation: .docked,
            entityID: "first-target-video-entity"
        )
        try runtime.attach(
            entityID: "first-target-video-entity",
            realityViewID: "first-target-reality-view",
            presentation: .docked
        )
        runtime.videoRendererTargetDidBind(
            revision: sourceVideoComponentRevision,
            entityID: "first-target-video-entity"
        )
        XCTAssertNil(runtime.boundVideoComponentRevision)
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "first-target-video-entity"
        )
        try await runtime.rebaseActivatedTechnicalSessionReplacement(to: .docked)
        try await waitUntilPlaybackLifecycle(runtime, equals: .paused)

        XCTAssertTrue(
            acceptedVideoSample(in: firstReplacementSession, covers: firstCutoverPosition)
        )
        XCTAssertEqual(runtime.productLifecycle, .paused)
        try await waitUntilDisplayedPixel(in: firstReplacementSession)
        runtime.recordPresentationState(
            presentation: .docked,
            phase: .settled,
            entityID: "first-target-video-entity",
            technicalSessionID: runtime.activeTechnicalSessionID,
            videoComponentRevision: runtime.videoComponentRevision,
            streamEpoch: firstReplacementSession.debugSnapshot().streamEpoch,
            realityViewID: "first-target-reality-view",
            displayedPixelBuffer: true
        )
        let firstReplacementSettled = await runtime.waitUntilPresentationSettled(
            to: .docked
        )
        XCTAssertTrue(firstReplacementSettled)
        XCTAssertEqual(runtime.technicalSessionReplacementStage, .completed)
        try await runtime.beginPlaybackForPresentationSettlement(
            mediaSessionID: logicalSessionID
        )
        try await waitUntilPlaybackLifecycle(runtime, equals: .playing)
        XCTAssertEqual(runtime.productLifecycle, .playing)
        sourceViewHost.close()
        await runtime.retireDepartingTechnicalSessionAfterSceneDisappearance()

        try await runtime.performSpatialPlaybackTransport(
            .pause(mediaSessionID: logicalSessionID)
        )
        try await waitUntilPlaybackLifecycle(runtime, equals: .paused)
        let pausedSourcePosition = firstReplacementSession.currentTime()
        let firstReplacementTechnicalSessionID = try XCTUnwrap(
            runtime.activeTechnicalSessionID
        )
        try await runtime.prepareTechnicalSessionForPresentationConversion()
        XCTAssertEqual(
            CMTimeCompare(firstReplacementSession.currentTime(), pausedSourcePosition),
            0
        )
        try await runtime.activatePreparedTechnicalSessionReplacement()

        let pausedReplacementSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let secondCutoverPosition = firstReplacementSession.currentTime()
        XCTAssertEqual(CMTimeCompare(secondCutoverPosition, pausedSourcePosition), 0)
        XCTAssertEqual(runtime.activeSessionID, logicalSessionID)
        XCTAssertNotEqual(runtime.activeTechnicalSessionID, firstReplacementTechnicalSessionID)
        XCTAssertEqual(runtime.currentAudioTrackID, selectedAudioTrack.id)
        XCTAssertEqual(runtime.currentSubtitleTrackID, selectedSubtitleTrack.id)
        XCTAssertNotEqual(runtime.productLifecycle, .playing)

        let pausedTargetEntity = Entity()
        PlaybackRealityPresenter.configure(
            pausedTargetEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        let pausedTargetViewHost = try PlaybackRealityViewTestHost(entity: pausedTargetEntity)
        defer { pausedTargetViewHost.close() }
        try await pausedTargetViewHost.waitUntilReady()
        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "paused-target-video-entity"
        )
        try runtime.attach(
            entityID: "paused-target-video-entity",
            realityViewID: "paused-target-reality-view",
            presentation: .window
        )
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "paused-target-video-entity"
        )
        try await runtime.rebaseActivatedTechnicalSessionReplacement(to: .window)
        try await waitUntilPlaybackLifecycle(runtime, equals: .paused)

        XCTAssertTrue(
            acceptedVideoSample(in: pausedReplacementSession, covers: secondCutoverPosition)
        )
        XCTAssertEqual(runtime.productLifecycle, .paused)
        try await waitUntilDisplayedPixel(in: pausedReplacementSession)
        runtime.recordPresentationState(
            presentation: .window,
            phase: .settled,
            entityID: "paused-target-video-entity",
            technicalSessionID: runtime.activeTechnicalSessionID,
            videoComponentRevision: runtime.videoComponentRevision,
            streamEpoch: pausedReplacementSession.debugSnapshot().streamEpoch,
            realityViewID: "paused-target-reality-view",
            displayedPixelBuffer: true
        )
        let pausedReplacementSettled = await runtime.waitUntilPresentationSettled(
            to: .window
        )
        XCTAssertTrue(pausedReplacementSettled)
        XCTAssertNotNil(sourceEntity.components[VideoPlayerComponent.self])
        XCTAssertNotNil(firstTargetEntity.components[VideoPlayerComponent.self])
        XCTAssertNotNil(pausedTargetEntity.components[VideoPlayerComponent.self])
        firstTargetViewHost.close()
        await runtime.retireDepartingTechnicalSessionAfterSceneDisappearance()
    }

    @MainActor
    func testEndedTechnicalSessionReplacementDeliversFinalFrameAndReplayStartsAtZero()
        async throws {
        let fixture = URL(
            fileURLWithPath:
                "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv"
        )
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("The multi-track playback fixture is not available in this test process.")
        }
        let runtime = PlaybackRuntime()
        addTeardownBlock { @MainActor in
            await runtime.stopAndWait()
        }
        var naturalEndCount = 0
        runtime.onPlaybackEnded = {
            naturalEndCount += 1
        }
        try await runtime.open(
            PlaybackLaunchRequest(
                url: fixture,
                displayName: fixture.lastPathComponent
            )
        )
        let logicalSessionID = try XCTUnwrap(runtime.activeSessionID)
        let sourceSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let sourceEntity = Entity()
        PlaybackRealityPresenter.configure(
            sourceEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        let sourceViewHost = try PlaybackRealityViewTestHost(entity: sourceEntity)
        defer { sourceViewHost.close() }
        try await sourceViewHost.waitUntilReady()
        try runtime.attach(
            entityID: "ended-source-video-entity",
            realityViewID: "ended-source-reality-view",
            presentation: .window
        )
        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "ended-source-video-entity"
        )
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "ended-source-video-entity"
        )
        try await runtime.beginPlaybackForPresentationSettlement(
            mediaSessionID: logicalSessionID
        )
        _ = try await waitUntilPlaybackAdvances(runtime, sourceSession, beyond: .zero)
        runtime.seek(to: max(0, runtime.playbackPosition.duration - 1))
        try await waitUntilSeekCompletes(runtime)
        try await waitUntilPlaybackLifecycle(runtime, equals: .ended)

        let logicalEndPosition = runtime.playbackPosition.duration
        let finalDisplayTime = try XCTUnwrap(
            sourceSession.finalDisplayableVideoPresentationTime
        )
        XCTAssertTrue(runtime.didEndNaturally)
        XCTAssertEqual(naturalEndCount, 1)

        try await runtime.prepareTechnicalSessionForPresentationConversion()
        try await runtime.activatePreparedTechnicalSessionReplacement()
        let replacementSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let targetEntity = Entity()
        PlaybackRealityPresenter.configure(
            targetEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .docked,
            requestsSpatialVideoMode: false
        )
        let targetViewHost = try PlaybackRealityViewTestHost(entity: targetEntity)
        defer { targetViewHost.close() }
        try await targetViewHost.waitUntilReady()
        try runtime.claimRendererConsumer(
            presentation: .docked,
            entityID: "ended-target-video-entity"
        )
        try runtime.attach(
            entityID: "ended-target-video-entity",
            realityViewID: "ended-target-reality-view",
            presentation: .docked
        )
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "ended-target-video-entity"
        )
        try await runtime.rebaseActivatedTechnicalSessionReplacement(to: .docked)
        try await waitUntilAcceptedVideoSample(
            in: replacementSession,
            covers: finalDisplayTime
        )
        try await waitUntilDisplayedPixel(in: replacementSession)
        runtime.recordPresentationState(
            presentation: .docked,
            phase: .settled,
            entityID: "ended-target-video-entity",
            technicalSessionID: runtime.activeTechnicalSessionID,
            videoComponentRevision: runtime.videoComponentRevision,
            streamEpoch: replacementSession.debugSnapshot().streamEpoch,
            realityViewID: "ended-target-reality-view",
            displayedPixelBuffer: true
        )

        let endedReplacementSettled = await runtime.waitUntilPresentationSettled(
            to: .docked
        )
        XCTAssertTrue(endedReplacementSettled)
        XCTAssertEqual(runtime.productLifecycle, .ended)
        XCTAssertEqual(runtime.playbackPosition.seconds, logicalEndPosition, accuracy: 0.001)
        XCTAssertTrue(runtime.didEndNaturally)
        XCTAssertEqual(naturalEndCount, 1)

        sourceViewHost.close()
        await runtime.retireDepartingTechnicalSessionAfterSceneDisappearance()
        let endedStreamEpoch = replacementSession.debugSnapshot().streamEpoch
        let replayEvents = replacementSession.debugEvents()
        let replaySeekCompletion = Task {
            for await event in replayEvents {
                if event.kind == "control.seek.completed",
                   let target = event.details["targetSeconds"].flatMap(Double.init) {
                    return target
                }
            }
            throw PlaybackRealityViewTestHostError.seekDidNotComplete
        }
        defer { replaySeekCompletion.cancel() }
        runtime.replay()
        try await waitUntilPlaybackLifecycle(runtime, equals: .playing)
        _ = try await waitUntilVideoStreamEpochAdvances(
            in: replacementSession,
            beyond: endedStreamEpoch
        )
        let replayTarget = try await replaySeekCompletion.value
        XCTAssertEqual(replayTarget, 0, accuracy: 0.001)
    }

    @MainActor
    func testRapidFrameStepBurstCoalescesIntoOneFurtherStepAndNeverAlerts() async throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-video-only-15s.mp4"
            )
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("The video-only playback fixture is not available in this test process.")
        }
        let runtime = PlaybackRuntime()
        addTeardownBlock { @MainActor in
            await runtime.stopAndWait()
        }
        try await runtime.open(
            PlaybackLaunchRequest(
                url: fixture,
                displayName: fixture.lastPathComponent
            )
        )
        let logicalSessionID = try XCTUnwrap(runtime.activeSessionID)
        let sourceSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let sourceEntity = Entity()
        PlaybackRealityPresenter.configure(
            sourceEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        let sourceViewHost = try PlaybackRealityViewTestHost(entity: sourceEntity)
        defer { sourceViewHost.close() }
        try await sourceViewHost.waitUntilReady()
        try runtime.attach(
            entityID: "frame-step-burst-video-entity",
            realityViewID: "frame-step-burst-reality-view",
            presentation: .window
        )
        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "frame-step-burst-video-entity"
        )
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "frame-step-burst-video-entity"
        )
        try await runtime.beginPlaybackForPresentationSettlement(
            mediaSessionID: logicalSessionID
        )
        _ = try await waitUntilPlaybackAdvances(runtime, sourceSession, beyond: .zero)
        runtime.pause()
        try await waitUntilPlaybackLifecycle(runtime, equals: .paused)

        let basePositionSeconds = sourceSession.currentTime().seconds
        let nominalFrameRate = runtime.diagnostics.nominalFrameRate
        let frameSeconds = nominalFrameRate > 0 ? 1 / nominalFrameRate : 1.0 / 30

        var completedPositions: [Double] = []
        runtime.onPlaybackObservation = { observation in
            if case .seekCompleted(let positionSeconds) = observation.event {
                completedPositions.append(positionSeconds)
            }
        }
        defer { runtime.onPlaybackObservation = nil }

        runtime.frameStepForward()
        await Task.yield()
        runtime.frameStepForward()
        runtime.frameStepForward()
        runtime.frameStepForward()
        runtime.frameStepForward()

        let firstFrameAfterBase = (floor(basePositionSeconds / frameSeconds + 0.001) + 1) * frameSeconds
        let expectedFinalPosition = firstFrameAfterBase + 4 * frameSeconds
        let clock = ContinuousClock()
        let startedAt = clock.now
        while completedPositions.last.map({
            abs($0 - expectedFinalPosition) > 0.002
        }) ?? true {
            guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
                throw PlaybackRealityViewTestHostError.seekDidNotComplete
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(completedPositions.count, 2)
        XCTAssertEqual(
            sourceSession.currentTime().seconds,
            expectedFinalPosition,
            accuracy: 0.002
        )
        XCTAssertNil(runtime.userVisibleIssue)
        XCTAssertEqual(sourceSession.debugSnapshot().lastError, nil)
    }

    @MainActor
    func testTheSameFileReachesThePlaybackCoreIdenticallyThroughEveryRoute() async throws {
        let vectors = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestMedia/TestVectors/Enchron/PlaybackBehavior")
        let fixtures = [
            "sdr-bframe-multiaudio-subtitles-30s.mkv",
            "sdr-bframe-video-only-15s.mp4"
        ].map { vectors.appendingPathComponent($0) }
        guard fixtures.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("The playback behavior fixtures are not available in this test process.")
        }
        for fixture in fixtures {
            let name = fixture.lastPathComponent
            let size = Int64(try XCTUnwrap(
                try FileManager.default.attributesOfItem(atPath: fixture.path)[.size] as? NSNumber
            ).int64Value)
            let local = try await observePlaybackRoute(
                PlaybackLaunchRequest(url: fixture, displayName: name)
            )
            XCTAssertNotEqual(local.dimensions, "—", name)
            XCTAssertTrue(local.seekLandedWithinOneSecond, name)
            if fixture.pathExtension == "mkv" {
                XCTAssertGreaterThan(local.audioTracks.count, 1, name)
                XCTAssertFalse(local.subtitleTracks.isEmpty, name)
            }

            let shareHandle = try await MediaByteStreamServer.shared.register(
                source: ParityFileByteRangeSource(fileURL: fixture, length: size),
                filename: name,
                preferredBufferDepth: .automatic
            )
            defer { shareHandle.release() }
            let share = try await observePlaybackRoute(PlaybackLaunchRequest(
                source: PlaybackAddress(byteStreamHandle: shareHandle),
                displayName: name
            ))
            XCTAssertEqual(share, local, "the SMB/WebDAV shape diverged for \(name)")

            ParityEmbyURLProtocol.serve(fixture, token: "parity-token")
            defer { ParityEmbyURLProtocol.serve(nil, token: "") }
            let embyHandle = try await MediaByteStreamServer.shared.register(
                source: EmbyMediaByteSource(
                    streamURL: try XCTUnwrap(URL(
                        string: "https://emby.parity.test/emby/Videos/1/stream?Static=true&MediaSourceId=source"
                    )),
                    accessToken: "parity-token",
                    contentLength: size,
                    session: ParityEmbyURLProtocol.makeSession()
                ),
                filename: fixture.deletingPathExtension().lastPathComponent,
                preferredBufferDepth: .automatic
            )
            defer { embyHandle.release() }
            let emby = try await observePlaybackRoute(PlaybackLaunchRequest(
                source: PlaybackAddress(byteStreamHandle: embyHandle),
                displayName: fixture.deletingPathExtension().lastPathComponent,
                initialMetadata: PlaybackMediaMetadata(fileSizeInBytes: size, overview: nil),
                viewingStateAuthority: .mediaServer
            ))
            XCTAssertEqual(emby, local, "the Emby shape diverged for \(name)")
        }
    }

    @MainActor
    func testTheSameFileReachesThePlaybackCoreIdenticallyThroughTheLiveShares() async throws {
        let workspace = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let services = workspace.appendingPathComponent("test-services")
        guard let webDAV = try LiveWebDAVIdentity.load(from: services),
              let smb = try LiveSMBIdentity.load(from: services) else {
            throw XCTSkip(
                "Run Scripts/verification/ensure_test_services.py so test-services/{webdav,smb}/runtime.json exist."
            )
        }
        let name = "sdr-bframe-aggregate-30s.mkv"
        let fixture = workspace.appendingPathComponent(
            "TestMedia/TestVectors/Enchron/PlaybackBehavior/\(name)"
        )
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("The aggregate playback fixture is not available in this test process.")
        }
        ServerTrustPolicy.shared.approvalHandler = { _ in true }
        defer { ServerTrustPolicy.shared.approvalHandler = nil }
        CleartextExposurePolicy.shared.approvalHandler = { _ in true }
        defer { CleartextExposurePolicy.shared.approvalHandler = nil }

        let local = try await observePlaybackRoute(
            PlaybackLaunchRequest(url: fixture, displayName: name)
        )
        XCTAssertGreaterThan(local.audioTracks.count, 1)
        XCTAssertFalse(local.subtitleTracks.isEmpty)
        XCTAssertNotEqual(local.dimensions, "—")

        let credentials = ParityCredentialStore()
        let webDAVInfo = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: webDAV.address,
            username: webDAV.user
        )
        try credentials.saveCredential(
            for: webDAVInfo.credentialSourceID,
            credential: StorageCredential(username: webDAV.user, password: webDAV.password)
        )
        let webDAVAdapter = WebDAVDataSourceAdapter(credentialStore: credentials)
        try await webDAVAdapter.connect(with: webDAVInfo)
        defer { webDAVAdapter.disconnect() }
        let webDAVListing = try await webDAVAdapter.listContents(at: webDAVInfo.rootPath)
        let webDAVFile = try XCTUnwrap(
            webDAVListing.first { $0.name == name },
            "the WebDAV regression collection does not serve \(name)"
        )
        let webDAVSource = try await webDAVAdapter.resolvePlayableSource(for: webDAVFile)
        defer {
            webDAVSource.byteStreamHandle?.release()
            webDAVSource.accessLease?.release()
        }
        let overWebDAV = try await observePlaybackRoute(PlaybackLaunchRequest(
            source: PlaybackAddress(byteStreamHandle: try XCTUnwrap(webDAVSource.byteStreamHandle)),
            displayName: webDAVFile.name
        ))
        XCTAssertEqual(overWebDAV, local, "the live WebDAV route diverged for \(name)")

        let smbInfo = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: smb.address,
            username: smb.user
        )
        try credentials.saveCredential(
            for: smbInfo.credentialSourceID,
            credential: StorageCredential(username: smb.user, password: smb.password)
        )
        let smbAdapter = SMBDataSourceAdapter(credentialStore: credentials)
        try await smbAdapter.connect(with: smbInfo)
        defer { smbAdapter.disconnect() }
        let smbFolder = "/\(smb.shareName)/TestVectors/Enchron/PlaybackBehavior"
        let smbListing = try await smbAdapter.listContents(at: smbFolder)
        let smbFile = try XCTUnwrap(
            smbListing.first { $0.name == name },
            "the SMB share does not list \(name) under \(smbFolder)"
        )
        let smbSource = try await smbAdapter.resolvePlayableSource(for: smbFile)
        defer {
            smbSource.byteStreamHandle?.release()
            smbSource.accessLease?.release()
        }
        let overSMB = try await observePlaybackRoute(PlaybackLaunchRequest(
            source: PlaybackAddress(byteStreamHandle: try XCTUnwrap(smbSource.byteStreamHandle)),
            displayName: smbFile.name
        ))
        XCTAssertEqual(overSMB, local, "the live SMB route diverged for \(name)")
    }

    @MainActor
    private func observePlaybackRoute(
        _ request: PlaybackLaunchRequest
    ) async throws -> PlaybackRouteObservation {
        let runtime = PlaybackRuntime()
        defer { Task { @MainActor in await runtime.stopAndWait() } }
        try await runtime.open(request)
        let logicalSessionID = try XCTUnwrap(runtime.activeSessionID)
        let session = try XCTUnwrap(runtime.activeSessionForVerification())
        let entity = Entity()
        PlaybackRealityPresenter.configure(
            entity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        let host = try PlaybackRealityViewTestHost(entity: entity)
        defer { host.close() }
        try await host.waitUntilReady()
        try runtime.attach(
            entityID: "route-video-entity",
            realityViewID: "route-reality-view",
            presentation: .window
        )
        try runtime.claimRendererConsumer(presentation: .window, entityID: "route-video-entity")
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "route-video-entity"
        )
        try await runtime.beginPlaybackForPresentationSettlement(mediaSessionID: logicalSessionID)
        _ = try await waitUntilPlaybackAdvances(runtime, session, beyond: .zero)
        let clock = ContinuousClock()
        let startedAt = clock.now
        while runtime.diagnostics.dimensions == "—" {
            guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
                throw PlaybackRealityViewTestHostError.playbackDidNotAdvance
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let diagnostics = runtime.diagnostics
        let seekTarget = min(8, max(1, diagnostics.durationSeconds - 3))
        runtime.seek(to: seekTarget, event: .progressBar)
        try await waitUntilSeekCompletes(runtime)
        let landed = try await waitUntilPlaybackAdvances(
            runtime,
            session,
            beyond: CMTime(seconds: seekTarget - 0.5, preferredTimescale: 600)
        )
        let observation = PlaybackRouteObservation(
            codecName: diagnostics.codecName,
            dimensions: diagnostics.dimensions,
            durationTenths: Int((diagnostics.durationSeconds * 10).rounded()),
            nominalFrameRateHundredths: Int((diagnostics.nominalFrameRate * 100).rounded()),
            audioTracks: runtime.availableAudioTracks.map {
                "\($0.id)|\($0.languageCode ?? "-")|\($0.displayName)"
            },
            subtitleTracks: runtime.availableSubtitleTracks.map {
                "\($0.id)|\($0.languageCode ?? "-")|\($0.displayName)"
            },
            seekLandedWithinOneSecond: abs(landed.seconds - seekTarget) < 1,
            userVisibleIssue: runtime.userVisibleIssue.map { String(describing: $0) }
        )
        await runtime.stopAndWait()
        return observation
    }

    @MainActor
    func testTechnicalSessionEndingAfterCutoverRebasesAtTheFinalFrame()
        async throws {
        let fixture = URL(
            fileURLWithPath:
                "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia/TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-subtitles-30s.mkv"
        )
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("The multi-track playback fixture is not available in this test process.")
        }
        let sourceController = PlaybackCoreController()
        let runtime = PlaybackRuntime(
            controller: sourceController,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
        addTeardownBlock { @MainActor in
            await runtime.stopAndWait()
        }
        var naturalEndCount = 0
        runtime.onPlaybackEnded = {
            naturalEndCount += 1
        }
        try await runtime.open(
            PlaybackLaunchRequest(
                url: fixture,
                displayName: fixture.lastPathComponent
            )
        )
        let logicalSessionID = try XCTUnwrap(runtime.activeSessionID)
        let sourceSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let sourceEntity = Entity()
        PlaybackRealityPresenter.configure(
            sourceEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        let sourceViewHost = try PlaybackRealityViewTestHost(entity: sourceEntity)
        defer { sourceViewHost.close() }
        try await sourceViewHost.waitUntilReady()
        try runtime.attach(
            entityID: "late-end-source-video-entity",
            realityViewID: "late-end-source-reality-view",
            presentation: .window
        )
        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "late-end-source-video-entity"
        )
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "late-end-source-video-entity"
        )
        try await runtime.beginPlaybackForPresentationSettlement(
            mediaSessionID: logicalSessionID
        )
        _ = try await waitUntilPlaybackAdvances(runtime, sourceSession, beyond: .zero)
        runtime.seek(to: max(0, runtime.playbackPosition.duration - 8))
        try await waitUntilSeekCompletes(runtime)

        try await runtime.prepareTechnicalSessionForPresentationConversion()
        try await runtime.activatePreparedTechnicalSessionReplacement()
        let replacementSession = try XCTUnwrap(runtime.activeSessionForVerification())
        let targetEntity = Entity()
        PlaybackRealityPresenter.configure(
            targetEntity,
            renderer: try XCTUnwrap(runtime.renderer),
            presentation: .portal,
            requestsSpatialVideoMode: false
        )
        let targetViewHost = try PlaybackRealityViewTestHost(entity: targetEntity)
        defer { targetViewHost.close() }
        try await targetViewHost.waitUntilReady()
        try runtime.claimRendererConsumer(
            presentation: .portal,
            entityID: "late-end-target-video-entity"
        )
        try runtime.attach(
            entityID: "late-end-target-video-entity",
            realityViewID: "late-end-target-reality-view",
            presentation: .portal
        )
        runtime.videoRendererTargetDidBind(
            revision: runtime.videoComponentRevision,
            entityID: "late-end-target-video-entity"
        )
        try await runtime.rebaseActivatedTechnicalSessionReplacement(to: .portal)
        try sourceController.play()
        try await waitUntilControllerEnds(sourceController)
        let finalDisplayTime = try XCTUnwrap(
            sourceSession.finalDisplayableVideoPresentationTime
        )
        let settlement = Task { @MainActor in
            await runtime.waitUntilPresentationSettled(to: .portal)
        }
        try await waitUntilAcceptedVideoSample(
            in: replacementSession,
            covers: finalDisplayTime
        )
        try await waitUntilDisplayedPixel(in: replacementSession)
        runtime.recordPresentationState(
            presentation: .portal,
            phase: .settled,
            entityID: "late-end-target-video-entity",
            technicalSessionID: runtime.activeTechnicalSessionID,
            videoComponentRevision: runtime.videoComponentRevision,
            streamEpoch: replacementSession.debugSnapshot().streamEpoch,
            realityViewID: "late-end-target-reality-view",
            displayedPixelBuffer: true
        )

        let lateEndReplacementSettled = await settlement.value
        XCTAssertTrue(lateEndReplacementSettled)
        XCTAssertEqual(runtime.productLifecycle, .ended)
        XCTAssertEqual(
            runtime.playbackPosition.seconds,
            runtime.playbackPosition.duration,
            accuracy: 0.001
        )
        XCTAssertTrue(runtime.didEndNaturally)
        XCTAssertEqual(naturalEndCount, 1)

        sourceViewHost.close()
        await runtime.retireDepartingTechnicalSessionAfterSceneDisappearance()
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
    func testOnlyPortalToPanoramaRetiresTheSourceSessionBeforeDelivery() {
        XCTAssertTrue(
            PlaybackRuntime.shouldRetireDepartingTechnicalSessionBeforeDelivery(
                from: .portal,
                to: .panorama
            )
        )
        XCTAssertFalse(
            PlaybackRuntime.shouldRetireDepartingTechnicalSessionBeforeDelivery(
                from: .window,
                to: .docked
            )
        )
        XCTAssertFalse(
            PlaybackRuntime.shouldRetireDepartingTechnicalSessionBeforeDelivery(
                from: .panorama,
                to: .portal
            )
        )
    }

    @MainActor
    func testSecondRequestTakesTheRendererWhenTheSurfaceNeverReleasedIt() throws {
        let runtime = PlaybackRuntime()
        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "window-entity-first-request"
        )

        runtime.stop()
        runtime.prepareForPlayback(
            PlaybackLaunchRequest(
                url: URL(fileURLWithPath: "/dev/null"),
                displayName: "second.mp4"
            )
        )

        try runtime.claimRendererConsumer(
            presentation: .window,
            entityID: "window-entity-second-request"
        )

        XCTAssertEqual(runtime.rendererConsumerPresentation, .window)
        XCTAssertEqual(
            runtime.rendererConsumerEntityID,
            "window-entity-second-request"
        )
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
        let appModel = PlaybackSessionModel()
        let entered = Date(timeIntervalSince1970: 100)
        let exited = Date(timeIntervalSince1970: 105)

        appModel.setControlsFocused(true, at: entered)
        appModel.setControlsFocused(false, at: exited)

        XCTAssertFalse(appModel.isControlsFocused)
        XCTAssertEqual(appModel.lastControlsInteractionAt, exited)
    }

}

@MainActor
private final class PlaybackRealityViewTestHost {
    private let readiness = PlaybackRealityViewTestReadiness()
    private let controller: UIHostingController<PlaybackRealityViewTestSurface>
    private let window: UIWindow
    private var isClosed = false

    init(entity: Entity) throws {
        let readiness = self.readiness
        controller = UIHostingController(
            rootView: PlaybackRealityViewTestSurface(
                entity: entity,
                onReady: { readiness.markReady() }
            )
        )
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            throw PlaybackRealityViewTestHostError.missingWindow
        }
        window = UIWindow(windowScene: windowScene)
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        window.rootViewController = controller
        window.isHidden = false
    }

    func waitUntilReady() async throws {
        try await readiness.waitUntilReady(
            deadline: PlaybackRuntime.presentationSettlementDeadline
        )
    }

    func close() {
        guard isClosed == false else { return }
        isClosed = true
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
private final class PlaybackRealityViewTestReadiness {
    private var isReady = false

    func markReady() {
        isReady = true
    }

    func waitUntilReady(deadline: Duration) async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now
        while isReady == false {
            guard clock.now - startedAt < deadline else {
                throw PlaybackRealityViewTestHostError.realityViewDidNotBecomeReady
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

@MainActor
private func waitUntilPlaybackAdvances(
    _ runtime: PlaybackRuntime,
    _ session: SampleBufferPlaybackSession,
    beyond time: CMTime
) async throws -> CMTime {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while true {
        let currentTime = session.currentTime()
        if runtime.productLifecycle == .playing,
           CMTimeCompare(currentTime, time) > 0 {
            return currentTime
        }
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.playbackDidNotAdvance
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitUntilPlaybackLifecycle(
    _ runtime: PlaybackRuntime,
    equals lifecycle: ProductPlaybackLifecycle
) async throws {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while runtime.productLifecycle != lifecycle {
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.playbackLifecycleDidNotSettle
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitUntilSeekCompletes(_ runtime: PlaybackRuntime) async throws {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while runtime.seekIsInProgress {
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.seekDidNotComplete
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitUntilAcceptedVideoSample(
    in session: SampleBufferPlaybackSession,
    covers time: CMTime
) async throws {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while true {
        let snapshot = session.debugSnapshot()
        if snapshot.lifecycle == .ended,
           let maximumPresentationTime = session.finalDisplayableVideoPresentationTime,
           CMTimeCompare(maximumPresentationTime, time) >= 0 {
            return
        }
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.videoSampleWasNotAccepted
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitUntilDisplayedPixel(
    in session: SampleBufferPlaybackSession
) async throws {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while session.renderer.displayedPixelBuffer() == nil {
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.displayedPixelDidNotAppear
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitUntilControllerEnds(
    _ controller: PlaybackCoreController
) async throws {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while true {
        if case .ended = controller.status { return }
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.playbackLifecycleDidNotSettle
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

@MainActor
private func waitUntilVideoStreamEpochAdvances(
    in session: SampleBufferPlaybackSession,
    beyond streamEpoch: UInt64
) async throws -> VideoSampleRecord {
    let clock = ContinuousClock()
    let startedAt = clock.now
    while true {
        if let sample = session.debugSnapshot().lastVideoSample,
           sample.streamEpoch > streamEpoch {
            return sample
        }
        guard clock.now - startedAt < PlaybackRuntime.presentationSettlementDeadline else {
            throw PlaybackRealityViewTestHostError.videoSampleWasNotAccepted
        }
        try await Task.sleep(for: .milliseconds(25))
    }
}

private func acceptedVideoSample(
    in session: SampleBufferPlaybackSession,
    covers time: CMTime
) -> Bool {
    guard let sample = session.debugSnapshot().lastVideoSample,
          sample.presentationTimeSeconds.isFinite,
          time.seconds.isFinite else {
        return false
    }
    if sample.presentationTimeSeconds >= time.seconds {
        return true
    }
    return sample.durationSeconds.isFinite
        && sample.durationSeconds > 0
        && sample.presentationTimeSeconds + sample.durationSeconds >= time.seconds
}

private struct PlaybackRealityViewTestSurface: View {
    let entity: Entity
    let onReady: @MainActor () -> Void

    var body: some View {
        RealityView { content in
            content.add(entity)
            onReady()
        }
    }
}

private enum PlaybackRealityViewTestHostError: Error {
    case missingWindow
    case realityViewDidNotBecomeReady
    case playbackDidNotAdvance
    case playbackLifecycleDidNotSettle
    case seekDidNotComplete
    case videoSampleWasNotAccepted
    case displayedPixelDidNotAppear
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

private struct PlaybackRouteObservation: Equatable {
    let codecName: String
    let dimensions: String
    let durationTenths: Int
    let nominalFrameRateHundredths: Int
    let audioTracks: [String]
    let subtitleTracks: [String]
    let seekLandedWithinOneSecond: Bool
    let userVisibleIssue: String?
}

nonisolated private final class ParityFileByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes
    private let fileURL: URL
    private let length: Int64

    init(fileURL: URL, length: Int64) {
        self.fileURL = fileURL
        self.length = length
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: length,
            supportsSeeking: true,
            isLive: false
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let start = min(range.lowerBound, length)
        let end = min(range.upperBound, length)
        try handle.seek(toOffset: UInt64(start))
        let data = end > start ? try handle.read(upToCount: Int(end - start)) ?? Data() : Data()
        return MediaByteRangeRead(data: data, contentLength: length, supportsSeeking: true)
    }
}

nonisolated private final class ParityEmbyServedFile: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var token = ""

    func serve(_ url: URL?, token: String) {
        let data = url.flatMap { try? Data(contentsOf: $0) }
        lock.withLock {
            self.data = data
            self.token = token
        }
    }

    func current() -> (Data, String)? {
        lock.withLock { data.map { ($0, token) } }
    }
}

nonisolated private final class ParityEmbyURLProtocol: URLProtocol {
    private static let served = ParityEmbyServedFile()

    static func serve(_ url: URL?, token: String) {
        served.serve(url, token: token)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ParityEmbyURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let (bytes, token) = Self.served.current(),
              request.value(forHTTPHeaderField: "X-Emby-Token") == token,
              let rangeHeader = request.value(forHTTPHeaderField: "Range"),
              rangeHeader.hasPrefix("bytes="),
              let response = Self.response(url: url, rangeHeader: rangeHeader, bytes: bytes) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func response(
        url: URL,
        rangeHeader: String,
        bytes: Data
    ) -> (HTTPURLResponse, Data)? {
        let bounds = rangeHeader.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]) else { return nil }
        let total = Int64(bytes.count)
        guard start < total else {
            return HTTPURLResponse(
                url: url,
                statusCode: 416,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Range": "bytes */\(total)"]
            ).map { ($0, Data()) }
        }
        let end = min(Int64(bounds[1]) ?? total - 1, total - 1)
        let body = bytes[Int(start)...Int(end)]
        return HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Range": "bytes \(start)-\(end)/\(total)",
                "Content-Length": "\(body.count)",
                "Content-Type": "application/octet-stream"
            ]
        ).map { ($0, Data(body)) }
    }
}

private struct LiveWebDAVIdentity: Decodable {
    let address: String
    let user: String
    let password: String

    static func load(from services: URL) throws -> LiveWebDAVIdentity? {
        let file = services.appendingPathComponent("webdav/runtime.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(LiveWebDAVIdentity.self, from: Data(contentsOf: file))
    }
}

private struct LiveSMBIdentity: Decodable {
    let address: String
    let user: String
    let password: String
    let shareName: String

    static func load(from services: URL) throws -> LiveSMBIdentity? {
        let file = services.appendingPathComponent("smb/runtime.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(LiveSMBIdentity.self, from: Data(contentsOf: file))
    }
}

nonisolated private final class ParityCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [String: StorageCredential] = [:]

    func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        lock.withLock { credentials[sourceID] = credential }
    }

    func loadCredential(for sourceID: String) throws -> StorageCredential? {
        lock.withLock { credentials[sourceID] }
    }

    func deleteCredential(for sourceID: String) throws {
        lock.withLock { credentials[sourceID] = nil }
    }
}
