import Foundation
import MediaSource
import PlaybackFeature
import Synchronization
import Testing

@MainActor
struct TrackSelectionPreferenceTests {
    @Test("playback mode persists independently from Media Format")
    func playbackModePersistsIndependentlyFromMediaFormat() async throws {
        let suiteName = "app.enchron.tests.playback-mode.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let identity = try #require(Self.request(revision: "revision-a").versionedIdentity)
        let store = MediaStateStore(suiteName: suiteName)

        await store.saveFormat(
            MediaFormat(
                projection: .equirectangular180,
                stereoLayout: .sideBySide
            ),
            for: identity
        )
        await store.savePlaybackMode(.window, for: identity)
        await store.resetFormat(for: identity)

        let state = try #require(await store.loadValidated(for: identity))
        #expect(state.formatPreference == nil)
        #expect(state.playbackModePreference == .window)
    }

    @Test("cold playback delivers its persisted panoramic family without consulting Media Format")
    func coldPlaybackDeliversPersistedPanoramicFamily() async throws {
        let suiteName = "app.enchron.tests.cold-playback-mode.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let identity = try #require(request.versionedIdentity)
        let store = MediaStateStore(suiteName: suiteName)
        await store.savePlaybackMode(.panorama, for: identity)

        let runtime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
        var resolvedMode: PersistedPlaybackMode?
        coordinator.onPlaybackModeEntryStarted = { mode, isColdLaunch in
            #expect(isColdLaunch)
            resolvedMode = mode
            return mode
        }
        coordinator.beginPlayback(request)
        try await runtime.waitUntilConfigured()

        #expect(resolvedMode == .panorama)
        #expect(runtime.lastAppliedFormat == nil)
    }

    @Test("source facts and user overrides use one effective format resolver")
    func sourceFactsAndOverridesUseOneEffectiveFormatResolver() {
        let source = SourceMediaFormatFact(
            contentKind: .halfEquirectangular,
            projection: .equirectangular180,
            stereoLayout: .multiview
        )

        let automatic = MediaFormatInterpretationResolver.resolve(
            source: source,
            override: nil
        )
        #expect(automatic.provenance == .source)
        #expect(automatic.projection == .equirectangular180)
        #expect(automatic.stereoLayout == .multiview)
        #expect(automatic.isPanoramic)

        let override = MediaFormatInterpretationResolver.resolve(
            source: source,
            override: .standard
        )
        #expect(override.provenance == .userOverride)
        #expect(override.projection == .flat)
        #expect(override.stereoLayout == .mono)
        #expect(override.isPanoramic == false)
    }

    @Test("media without a saved interpretation keeps the source format")
    func mediaWithoutSavedInterpretationKeepsSourceFormat() async throws {
        let suiteName = "app.enchron.tests.source-format.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let runtime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)

        coordinator.beginPlayback(Self.request(revision: "revision-a"))
        try await runtime.waitUntilConfigured()

        #expect(runtime.sourceFormatApplicationCount == 1)
        #expect(runtime.formatApplicationCount == 0)
    }

    @Test("a saved format override is restored for the same media revision")
    func savedFormatOverrideIsRestored() async throws {
        let suiteName = "app.enchron.tests.saved-format.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let firstRuntime = TrackSelectionRuntime()
        let firstCoordinator = Self.coordinator(runtime: firstRuntime, suiteName: suiteName)
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilConfigured()

        try await firstCoordinator.applyFormat(
            projection: .customAngle,
            horizontalFieldOfViewDegrees: 230,
            stereo: .sideBySide
        )

        let reopenedRuntime = TrackSelectionRuntime()
        let reopenedCoordinator = Self.coordinator(runtime: reopenedRuntime, suiteName: suiteName)
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilConfigured()

        #expect(reopenedRuntime.lastAppliedFormat?.projection == .customAngle)
        #expect(reopenedRuntime.lastAppliedFormat?.horizontalFieldOfViewDegrees == 230)
        #expect(reopenedRuntime.lastAppliedFormat?.stereoLayout == .sideBySide)
    }

    @Test("Automatic removes the saved override and it stays removed after reopening")
    func automaticRemovesSavedOverride() async throws {
        let suiteName = "app.enchron.tests.reset-format.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let firstRuntime = TrackSelectionRuntime()
        let firstCoordinator = Self.coordinator(runtime: firstRuntime, suiteName: suiteName)
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilConfigured()
        try await firstCoordinator.applyFormat(
            projection: .equirectangular180,
            stereo: .topBottom
        )

        try await firstCoordinator.resetFormat()

        let reopenedRuntime = TrackSelectionRuntime()
        let reopenedCoordinator = Self.coordinator(runtime: reopenedRuntime, suiteName: suiteName)
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilConfigured()
        #expect(reopenedRuntime.sourceFormatApplicationCount == 1)
        #expect(reopenedRuntime.formatApplicationCount == 0)
    }

    @Test("a failed core format operation does not change persistence")
    func failedCoreFormatOperationDoesNotPersist() async throws {
        let suiteName = "app.enchron.tests.failed-format.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let runtime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
        coordinator.beginPlayback(request)
        try await runtime.waitUntilConfigured()
        runtime.nextFormatApplicationError = TrackSelectionRuntime.TestError.formatRejected

        await #expect(throws: TrackSelectionRuntime.TestError.formatRejected) {
            try await coordinator.applyFormat(
                projection: .equirectangular360,
                stereo: .mono
            )
        }

        let reopenedRuntime = TrackSelectionRuntime()
        let reopenedCoordinator = Self.coordinator(runtime: reopenedRuntime, suiteName: suiteName)
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilConfigured()
        #expect(reopenedRuntime.sourceFormatApplicationCount == 1)
        #expect(reopenedRuntime.formatApplicationCount == 0)
    }

    @Test("a newer format request supersedes an older request for the same session")
    func newerFormatRequestSupersedesOlderRequest() async throws {
        let suiteName = "app.enchron.tests.superseded-format.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let runtime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
        coordinator.beginPlayback(request)
        try await runtime.waitUntilConfigured()
        runtime.suspendNextFormatApplication()

        let olderRequest = Task { @MainActor in
            try await coordinator.applyFormat(
                projection: .equirectangular180,
                stereo: .sideBySide
            )
        }
        try await runtime.waitUntilFormatApplicationIsSuspended()
        let newerRequest = Task { @MainActor in
            try await coordinator.applyFormat(
                projection: .equirectangular360,
                stereo: .topBottom
            )
        }
        await Task.yield()
        runtime.resumeSuspendedFormatApplication()
        try await olderRequest.value
        try await newerRequest.value

        let reopenedRuntime = TrackSelectionRuntime()
        let reopenedCoordinator = Self.coordinator(runtime: reopenedRuntime, suiteName: suiteName)
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilConfigured()
        #expect(reopenedRuntime.lastAppliedFormat?.projection == .equirectangular360)
        #expect(reopenedRuntime.lastAppliedFormat?.stereoLayout == .topBottom)
    }

    @Test("switching media invalidates an unfinished format request without saving either identity")
    func switchingMediaInvalidatesUnfinishedFormatRequest() async throws {
        let suiteName = "app.enchron.tests.switched-format.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let firstRequest = Self.request(revision: "revision-a")
        let secondRequest = Self.request(revision: "revision-b")
        let runtime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
        coordinator.beginPlayback(firstRequest)
        try await runtime.waitUntilConfigured()
        let firstSessionID = runtime.activeSessionID
        runtime.suspendNextFormatApplication()

        let staleFormatRequest = Task { @MainActor in
            try await coordinator.applyFormat(
                projection: .equirectangular180,
                stereo: .sideBySide
            )
        }
        try await runtime.waitUntilFormatApplicationIsSuspended()
        coordinator.beginPlayback(secondRequest)
        try await runtime.waitUntilCurrentMediaIs(secondRequest, replacing: firstSessionID)
        runtime.resumeSuspendedFormatApplication()
        try await staleFormatRequest.value
        try await runtime.waitUntilConfigurationCountIs(3)

        for request in [firstRequest, secondRequest] {
            let reopenedRuntime = TrackSelectionRuntime()
            let reopenedCoordinator = Self.coordinator(
                runtime: reopenedRuntime,
                suiteName: suiteName
            )
            reopenedCoordinator.beginPlayback(request)
            try await reopenedRuntime.waitUntilConfigured()
            #expect(reopenedRuntime.sourceFormatApplicationCount == 1)
            #expect(reopenedRuntime.formatApplicationCount == 0)
        }
    }

    @Test("Start Over begins at zero without deleting saved progress")
    func startOverPreservesSavedProgress() async throws {
        let suiteName = "app.enchron.tests.start-over.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")

        let firstRuntime = TrackSelectionRuntime()
        let firstCoordinator = Self.coordinator(runtime: firstRuntime, suiteName: suiteName)
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilOpened()
        firstRuntime.playbackPosition = .init(seconds: 120, duration: 1_200)
        firstRuntime.actualPlaybackSeconds = 20
        firstCoordinator.stopPlayback()
        let identity = request.versionedIdentity!.mediaIdentity
        let persistedDeadline = ContinuousClock.now + .seconds(2)
        while await firstCoordinator.viewingState(for: identity) == nil,
              ContinuousClock.now < persistedDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        let resumeRuntime = TrackSelectionRuntime()
        let resumeCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: resumeRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: AskToResumePreferences()
        )
        resumeCoordinator.beginPlayback(request)
        let deadline = ContinuousClock.now + .seconds(2)
        while resumeCoordinator.pendingResumeDecision == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(resumeCoordinator.pendingResumeDecision?.seconds == 120)

        resumeCoordinator.startPendingPlaybackFromBeginning()
        try await resumeRuntime.waitUntilOpened()
        #expect(resumeRuntime.lastStartTimeSeconds == 0)
        #expect(resumeCoordinator.pendingResumeDecision == nil)

        let state = await resumeCoordinator.viewingState(
            for: identity
        )
        guard case .resumable(let seconds, _) = state else {
            Issue.record("Start Over removed the saved resumable state")
            return
        }
        #expect(seconds == 120)
    }

    @Test("reopening unchanged media restores the selected audio track")
    func reopeningUnchangedMediaRestoresSelectedAudioTrack() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let preferredTrack = PlaybackModel.AudioTrack(
            id: "audio.commentary",
            languageCode: "en",
            displayName: "English Commentary"
        )

        let firstRuntime = TrackSelectionRuntime(
            audioTracks: [
                .init(id: "audio.main", languageCode: "en", displayName: "English", isDefault: true),
                preferredTrack,
            ]
        )
        let firstCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: firstRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilOpened()

        try await firstCoordinator.selectAudioTrack(preferredTrack)
        #expect(firstRuntime.currentAudioTrackID == preferredTrack.id)

        let reopenedRuntime = TrackSelectionRuntime(audioTracks: firstRuntime.availableAudioTracks)
        let reopenedCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: reopenedRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilOpened()
        try await reopenedRuntime.waitForAudioTrack(id: preferredTrack.id)

        #expect(reopenedRuntime.currentAudioTrackID == preferredTrack.id)
    }

    @Test("reopening unchanged media restores the selected subtitle track")
    func reopeningUnchangedMediaRestoresSelectedSubtitleTrack() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let preferredTrack = PlaybackModel.SubtitleTrack(
            id: "subtitle.zh-hans",
            languageCode: "zh-Hans",
            displayName: "简体中文"
        )
        let tracks = [
            PlaybackModel.SubtitleTrack(
                id: "subtitle.english",
                languageCode: "en",
                displayName: "English",
                isDefault: true
            ),
            preferredTrack,
        ]

        let firstRuntime = TrackSelectionRuntime(subtitleTracks: tracks)
        let firstCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: firstRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilOpened()

        try await firstCoordinator.selectSubtitleTrack(preferredTrack)
        #expect(firstRuntime.currentSubtitleTrackID == preferredTrack.id)

        let reopenedRuntime = TrackSelectionRuntime(subtitleTracks: tracks)
        let reopenedCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: reopenedRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilOpened()
        try await reopenedRuntime.waitForSubtitleTrack(id: preferredTrack.id)

        #expect(reopenedRuntime.currentSubtitleTrackID == preferredTrack.id)
    }

    @Test("reopening unchanged media keeps subtitles off when the user turned them off")
    func reopeningUnchangedMediaKeepsSubtitlesOff() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let defaultTrack = PlaybackModel.SubtitleTrack(
            id: "subtitle.english",
            languageCode: "en",
            displayName: "English",
            isDefault: true
        )

        let firstRuntime = TrackSelectionRuntime(subtitleTracks: [defaultTrack])
        let firstCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: firstRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilOpened()
        #expect(firstRuntime.currentSubtitleTrackID == defaultTrack.id)

        try await firstCoordinator.selectSubtitleTrack(nil)
        #expect(firstRuntime.currentSubtitleTrackID == nil)

        let reopenedRuntime = TrackSelectionRuntime(subtitleTracks: [defaultTrack])
        let reopenedCoordinator = PlaybackLaunchCoordinator(
            playbackRuntime: reopenedRuntime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilOpened()
        try await reopenedRuntime.waitForSubtitleTrack(id: nil)

        #expect(reopenedRuntime.currentSubtitleTrackID == nil)
    }

    @Test("audio and subtitle selections are restored together")
    func audioAndSubtitleSelectionsAreRestoredTogether() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let audioTracks = Self.audioTracks
        let subtitleTracks = Self.subtitleTracks
        let preferredAudio = audioTracks[1]
        let preferredSubtitle = subtitleTracks[1]

        let firstRuntime = TrackSelectionRuntime(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
        let firstCoordinator = Self.coordinator(
            runtime: firstRuntime,
            suiteName: suiteName
        )
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilConfigured()
        try await firstCoordinator.selectAudioTrack(preferredAudio)
        try await firstCoordinator.selectSubtitleTrack(preferredSubtitle)

        let reopenedRuntime = TrackSelectionRuntime(
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )
        let reopenedCoordinator = Self.coordinator(
            runtime: reopenedRuntime,
            suiteName: suiteName
        )
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilConfigured()

        #expect(reopenedRuntime.currentAudioTrackID == preferredAudio.id)
        #expect(reopenedRuntime.currentSubtitleTrackID == preferredSubtitle.id)
    }

    @Test("temporarily unavailable saved tracks are not guessed or forgotten")
    func temporarilyUnavailableTracksAreNotGuessedOrForgotten() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let preferredAudio = Self.audioTracks[1]
        let preferredSubtitle = Self.subtitleTracks[1]

        let firstRuntime = TrackSelectionRuntime(
            audioTracks: Self.audioTracks,
            subtitleTracks: Self.subtitleTracks
        )
        let firstCoordinator = Self.coordinator(runtime: firstRuntime, suiteName: suiteName)
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilConfigured()
        try await firstCoordinator.selectAudioTrack(preferredAudio)
        try await firstCoordinator.selectSubtitleTrack(preferredSubtitle)

        let unavailableRuntime = TrackSelectionRuntime(
            audioTracks: [Self.audioTracks[0]],
            subtitleTracks: [Self.subtitleTracks[0]]
        )
        let unavailableCoordinator = Self.coordinator(
            runtime: unavailableRuntime,
            suiteName: suiteName
        )
        unavailableCoordinator.beginPlayback(request)
        try await unavailableRuntime.waitUntilConfigured()
        #expect(unavailableRuntime.currentAudioTrackID == Self.audioTracks[0].id)
        #expect(unavailableRuntime.currentSubtitleTrackID == Self.subtitleTracks[0].id)
        #expect(unavailableRuntime.lastErrorMessage == nil)

        let returnedRuntime = TrackSelectionRuntime(
            audioTracks: Self.audioTracks,
            subtitleTracks: Self.subtitleTracks
        )
        let returnedCoordinator = Self.coordinator(runtime: returnedRuntime, suiteName: suiteName)
        returnedCoordinator.beginPlayback(request)
        try await returnedRuntime.waitUntilConfigured()
        #expect(returnedRuntime.currentAudioTrackID == preferredAudio.id)
        #expect(returnedRuntime.currentSubtitleTrackID == preferredSubtitle.id)
    }

    @Test("replaced media content does not reuse saved track selections")
    func replacedMediaContentDoesNotReuseSavedTrackSelections() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let preferredAudio = Self.audioTracks[1]
        let preferredSubtitle = Self.subtitleTracks[1]

        let firstRuntime = TrackSelectionRuntime(
            audioTracks: Self.audioTracks,
            subtitleTracks: Self.subtitleTracks
        )
        let firstCoordinator = Self.coordinator(runtime: firstRuntime, suiteName: suiteName)
        firstCoordinator.beginPlayback(Self.request(revision: "revision-a"))
        try await firstRuntime.waitUntilConfigured()
        try await firstCoordinator.selectAudioTrack(preferredAudio)
        try await firstCoordinator.selectSubtitleTrack(preferredSubtitle)

        let replacementRuntime = TrackSelectionRuntime(
            audioTracks: Self.audioTracks,
            subtitleTracks: Self.subtitleTracks
        )
        let replacementCoordinator = Self.coordinator(
            runtime: replacementRuntime,
            suiteName: suiteName
        )
        replacementCoordinator.beginPlayback(Self.request(revision: "revision-b"))
        try await replacementRuntime.waitUntilConfigured()

        #expect(replacementRuntime.currentAudioTrackID == Self.audioTracks[0].id)
        #expect(replacementRuntime.currentSubtitleTrackID == Self.subtitleTracks[0].id)
    }

    @Test("an automatically associated subtitle selection restores by stable identity")
    func automaticallyAssociatedSubtitleRestoresByStableIdentity() async throws {
        let suiteName = "app.enchron.tests.track-selection.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let request = Self.request(revision: "revision-a")
        let externalTrack = PlaybackModel.SubtitleTrack(
            id: "external.subtitle.stable-source.0",
            languageCode: "zh-Hans",
            displayName: "Movie.zh-Hans.srt"
        )

        let firstRuntime = TrackSelectionRuntime(
            subtitleTracks: [Self.subtitleTracks[0], externalTrack]
        )
        let firstCoordinator = Self.coordinator(runtime: firstRuntime, suiteName: suiteName)
        firstCoordinator.beginPlayback(request)
        try await firstRuntime.waitUntilConfigured()
        try await firstCoordinator.selectSubtitleTrack(externalTrack)
        #expect(firstRuntime.currentSubtitleTrackID == externalTrack.id)

        let reopenedRuntime = TrackSelectionRuntime(
            subtitleTracks: [Self.subtitleTracks[0], externalTrack]
        )
        let reopenedCoordinator = Self.coordinator(runtime: reopenedRuntime, suiteName: suiteName)
        reopenedCoordinator.beginPlayback(request)
        try await reopenedRuntime.waitUntilConfigured()

        #expect(reopenedRuntime.currentSubtitleTrackID == externalTrack.id)
    }

    @Test("launch request viewing authority defaults locally and survives metadata updates")
    func launchRequestViewingAuthorityContract() {
        let reporter = RecordingPlaybackSessionReporter()
        let request = Self.request(
            revision: "revision-a",
            authority: .mediaServer,
            startPositionSeconds: 37,
            reporter: reporter
        )
        let sameRequestWithAnotherReporter = Self.request(
            revision: "revision-a",
            authority: .mediaServer,
            startPositionSeconds: 37,
            reporter: RecordingPlaybackSessionReporter()
        )
        let differentStart = Self.request(
            revision: "revision-a",
            authority: .mediaServer,
            startPositionSeconds: 38,
            reporter: reporter
        )
        let defaultRequest = Self.request(revision: "revision-a")
        let updated = request.updating(
            metadata: PlaybackMediaMetadata(fileSizeInBytes: 2_048)
        )

        #expect(defaultRequest.viewingStateAuthority == .enchronPersistence)
        #expect(defaultRequest.startPositionSeconds == nil)
        #expect(defaultRequest.sessionReporter == nil)
        #expect(request == sameRequestWithAnotherReporter)
        #expect(request != differentStart)
        #expect(updated.viewingStateAuthority == .mediaServer)
        #expect(updated.startPositionSeconds == 37)
        #expect((updated.sessionReporter as AnyObject?) === reporter)
    }

    @Test("media server authority ignores local viewing and track state")
    func mediaServerAuthorityKeepsOnlyLocalPresentationPreferences() async throws {
        let suiteName = "app.enchron.tests.server-authority.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let reporter = RecordingPlaybackSessionReporter()
        let request = Self.request(
            revision: "revision-a",
            authority: .mediaServer,
            startPositionSeconds: 321,
            reporter: reporter
        )
        let identity = try #require(request.versionedIdentity)
        let seededViewingStatus = ViewingStatus.resumable(
            positionSeconds: 120,
            durationSeconds: 1_200
        )
        let store = MediaStateStore(suiteName: suiteName)
        await store.applyViewingMutation(.save(seededViewingStatus), for: identity)
        await store.saveAudioTrackSelection(id: Self.audioTracks[1].id, for: identity)
        await store.saveSubtitleTrackSelection(
            .track(id: Self.subtitleTracks[1].id),
            for: identity
        )
        await store.saveFormat(
            MediaFormat(projection: .equirectangular180, stereoLayout: .sideBySide),
            for: identity
        )
        await store.savePlaybackMode(.panorama, for: identity)

        let runtime = TrackSelectionRuntime(
            audioTracks: Self.audioTracks,
            subtitleTracks: Self.subtitleTracks
        )
        let coordinator = PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: AskToResumePreferences()
        )
        var resolvedMode: PersistedPlaybackMode?
        coordinator.onPlaybackModeEntryStarted = { mode, _ in
            resolvedMode = mode
            return mode
        }
        coordinator.beginPlayback(request)
        try await runtime.waitUntilConfigured()

        #expect(coordinator.pendingResumeDecision == nil)
        #expect(runtime.lastStartTimeSeconds == 321)
        #expect(runtime.currentAudioTrackID == Self.audioTracks[0].id)
        #expect(runtime.currentSubtitleTrackID == Self.subtitleTracks[0].id)
        #expect(runtime.lastAppliedFormat?.projection == .equirectangular180)
        #expect(resolvedMode == .panorama)

        try await coordinator.selectAudioTrack(Self.audioTracks[0])
        try await coordinator.selectSubtitleTrack(nil)
        try await coordinator.applyFormat(projection: .flat, stereo: .mono)
        coordinator.savePlaybackMode(.window)
        runtime.playbackPosition = .init(seconds: 480, duration: 1_200)
        runtime.actualPlaybackSeconds = 120
        coordinator.stopPlayback()
        try await Self.waitUntilPersistedState(
            in: store,
            identity: identity,
            satisfies: {
                $0.formatPreference == .standard && $0.playbackModePreference == .window
            }
        )

        let persisted = try #require(await store.loadValidated(for: identity))
        #expect(persisted.viewingStatus == seededViewingStatus)
        #expect(persisted.trackSelectionPreference?.audioTrackID == Self.audioTracks[1].id)
        #expect(
            persisted.trackSelectionPreference?.subtitleTrack
                == .track(id: Self.subtitleTracks[1].id)
        )
        #expect(persisted.formatPreference == .standard)
        #expect(persisted.playbackModePreference == .window)
    }

    @Test("media server reporting preserves cadence and immediate state")
    func mediaServerReportingPreservesCadenceAndImmediateState() async throws {
        let suiteName = "app.enchron.tests.server-reporting.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let reporter = RecordingPlaybackSessionReporter()
        let runtime = TrackSelectionRuntime(
            audioTracks: Self.audioTracks,
            subtitleTracks: Self.subtitleTracks
        )
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
        coordinator.beginPlayback(
            Self.request(
                revision: "revision-a",
                authority: .mediaServer,
                reporter: reporter
            )
        )
        try await runtime.waitUntilConfigured()

        runtime.emitLifecycle(.playing)
        runtime.emitDiagnostics(positionSeconds: 9, actualPlaybackSeconds: 9)
        runtime.emitDiagnostics(positionSeconds: 10, actualPlaybackSeconds: 25)
        runtime.emitLifecycle(.paused, positionSeconds: 12)
        runtime.emitSeekCompleted(positionSeconds: 42)
        try await coordinator.selectAudioTrack(Self.audioTracks[1])
        try await coordinator.selectSubtitleTrack(Self.subtitleTracks[1])
        runtime.emitLifecycle(.playing)
        runtime.emitDiagnostics(positionSeconds: 49, actualPlaybackSeconds: 29)
        runtime.emitDiagnostics(positionSeconds: 50, actualPlaybackSeconds: 30)
        coordinator.stopPlayback()

        let calls = reporter.calls
        #expect(calls.count == 9)
        #expect(calls[0] == .started(.init(
            positionSeconds: 0,
            isPaused: false,
            selectedAudioTrackID: Self.audioTracks[0].id,
            selectedSubtitleTrackID: Self.subtitleTracks[0].id
        )))
        #expect(calls[1].progressedReport?.positionSeconds == 10)
        #expect(calls[2].progressedReport?.isPaused == true)
        #expect(calls[2].progressedReport?.positionSeconds == 12)
        #expect(calls[3].progressedReport?.positionSeconds == 42)
        #expect(calls[4].progressedReport?.selectedAudioTrackID == Self.audioTracks[1].id)
        #expect(
            calls[5].progressedReport?.selectedSubtitleTrackID == Self.subtitleTracks[1].id
        )
        #expect(calls[6].progressedReport?.isPaused == false)
        #expect(calls[7].progressedReport?.positionSeconds == 50)
        #expect(calls[8].stoppedReport?.positionSeconds == 50)
        #expect(calls[8].stoppedReport?.selectedAudioTrackID == Self.audioTracks[1].id)
        #expect(calls[8].stoppedReport?.selectedSubtitleTrackID == Self.subtitleTracks[1].id)
    }

    @Test("coordinator and direct runtime stops each report once")
    func coordinatorAndDirectRuntimeStopsEachReportOnce() async throws {
        let suiteName = "app.enchron.tests.server-stop.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let coordinatorReporter = RecordingPlaybackSessionReporter()
        let coordinatorRuntime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(
            runtime: coordinatorRuntime,
            suiteName: suiteName
        )
        coordinator.beginPlayback(Self.request(
            revision: "coordinator-stop",
            authority: .mediaServer,
            reporter: coordinatorReporter
        ))
        try await coordinatorRuntime.waitUntilConfigured()
        coordinatorRuntime.emitLifecycle(.playing)
        coordinator.stopPlayback()
        coordinatorRuntime.emitStopped()
        coordinatorRuntime.emitLifecycle(.failed)
        #expect(coordinatorReporter.stoppedCount == 1)

        let runtimeReporter = RecordingPlaybackSessionReporter()
        let directRuntime = TrackSelectionRuntime()
        let directCoordinator = Self.coordinator(runtime: directRuntime, suiteName: suiteName)
        directCoordinator.beginPlayback(Self.request(
            revision: "runtime-stop",
            authority: .mediaServer,
            reporter: runtimeReporter
        ))
        try await directRuntime.waitUntilConfigured()
        directRuntime.emitLifecycle(.playing)
        let generation = directRuntime.observationGeneration
        directRuntime.stop(releasingSourceAccess: true)
        directRuntime.emitStopped(generation: generation)
        directRuntime.emitLifecycle(.ended, generation: generation)
        #expect(runtimeReporter.stoppedCount == 1)
    }

    @Test("replacement finishes interrupted reporting and ignores stale observations")
    func replacementFinishesInterruptedReportingAndIgnoresStaleObservations() async throws {
        let suiteName = "app.enchron.tests.server-replacement.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let firstReporter = RecordingPlaybackSessionReporter()
        let secondReporter = RecordingPlaybackSessionReporter()
        let runtime = TrackSelectionRuntime()
        let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
        runtime.suspendNextOpen()
        coordinator.beginPlayback(Self.request(
            revision: "first",
            authority: .mediaServer,
            reporter: firstReporter
        ))
        try await runtime.waitUntilOpenIsSuspended()
        let staleGeneration = runtime.observationGeneration

        coordinator.beginPlayback(Self.request(
            revision: "second",
            authority: .mediaServer,
            reporter: secondReporter
        ))
        try await runtime.waitUntilCurrentRevisionIs("second")
        runtime.resumeSuspendedOpen()
        await Task.yield()

        #expect(firstReporter.stoppedCount == 1)
        runtime.emitStopped(generation: staleGeneration)
        runtime.emitLifecycle(.failed, generation: staleGeneration)
        #expect(secondReporter.stoppedCount == 0)
        coordinator.stopPlayback()
        #expect(secondReporter.stoppedCount == 1)
    }

    @Test("natural end and runtime failure each report one stop")
    func naturalEndAndRuntimeFailureEachReportOneStop() async throws {
        let suiteName = "app.enchron.tests.server-terminal.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        for lifecycle in [ProductPlaybackLifecycle.ended, .failed] {
            let reporter = RecordingPlaybackSessionReporter()
            let runtime = TrackSelectionRuntime()
            let coordinator = Self.coordinator(runtime: runtime, suiteName: suiteName)
            coordinator.beginPlayback(Self.request(
                revision: lifecycle.rawValue,
                authority: .mediaServer,
                reporter: reporter
            ))
            try await runtime.waitUntilConfigured()
            runtime.emitLifecycle(.playing)
            runtime.emitLifecycle(lifecycle, positionSeconds: 75)
            runtime.emitStopped()
            runtime.emitLifecycle(lifecycle)

            #expect(reporter.stoppedCount == 1)
            #expect(reporter.calls.last?.stoppedReport?.positionSeconds == 75)
        }
    }

    private static let audioTracks = [
        PlaybackModel.AudioTrack(
            id: "audio.main",
            languageCode: "en",
            displayName: "English",
            isDefault: true
        ),
        PlaybackModel.AudioTrack(
            id: "audio.commentary",
            languageCode: "en",
            displayName: "English Commentary"
        ),
    ]

    private static let subtitleTracks = [
        PlaybackModel.SubtitleTrack(
            id: "subtitle.english",
            languageCode: "en",
            displayName: "English",
            isDefault: true
        ),
        PlaybackModel.SubtitleTrack(
            id: "subtitle.zh-hans",
            languageCode: "zh-Hans",
            displayName: "简体中文"
        ),
    ]

    private static func coordinator(
        runtime: TrackSelectionRuntime,
        suiteName: String
    ) -> PlaybackLaunchCoordinator {
        PlaybackLaunchCoordinator(
            playbackRuntime: runtime,
            mediaStateSuiteName: suiteName,
            preferencesProvider: StartFromBeginningPreferences()
        )
    }

    private static func request(
        revision: String,
        authority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        reporter: (any PlaybackSessionReporting)? = nil
    ) -> PlaybackLaunchRequest {
        let identity = VersionedMediaIdentity(
            mediaIdentity: .remote(sourceKey: "test-source", canonicalPath: "/Movie.mkv"),
            contentRevision: .remote(entityTag: revision, sizeInBytes: 1_024)
        )
        return PlaybackLaunchRequest(
            source: .localFile(url: URL(fileURLWithPath: "/Movie.mkv")),
            displayName: "Movie.mkv",
            versionedIdentity: identity,
            viewingStateAuthority: authority,
            startPositionSeconds: startPositionSeconds,
            sessionReporter: reporter
        )
    }

    private static func waitUntilPersistedState(
        in store: MediaStateStore,
        identity: VersionedMediaIdentity,
        satisfies predicate: (PersistedMediaState) -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if let state = await store.loadValidated(for: identity), predicate(state) {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Persisted media state did not reach the expected value")
    }
}

private struct StartFromBeginningPreferences: PlaybackPreferencesProviding {
    func loadPlaybackPreferences() -> PlaybackPreferences {
        PlaybackPreferences(resumePolicy: .alwaysStartFromBeginning)
    }
}

private struct AskToResumePreferences: PlaybackPreferencesProviding {
    func loadPlaybackPreferences() -> PlaybackPreferences {
        PlaybackPreferences(resumePolicy: .askEveryTime)
    }
}

private enum PlaybackSessionReporterCall: Equatable {
    case started(PlaybackSessionReport)
    case progressed(PlaybackSessionReport)
    case stopped(PlaybackSessionReport)

    var progressedReport: PlaybackSessionReport? {
        guard case .progressed(let report) = self else { return nil }
        return report
    }

    var stoppedReport: PlaybackSessionReport? {
        guard case .stopped(let report) = self else { return nil }
        return report
    }
}

private final class RecordingPlaybackSessionReporter: PlaybackSessionReporting {
    private let recordedCalls = Mutex<[PlaybackSessionReporterCall]>([])

    var calls: [PlaybackSessionReporterCall] {
        recordedCalls.withLock { $0 }
    }

    var stoppedCount: Int {
        calls.count { call in
            if case .stopped = call { true } else { false }
        }
    }

    func playbackStarted(_ report: PlaybackSessionReport) {
        recordedCalls.withLock {
            $0.append(.started(report))
        }
    }

    func playbackProgressed(_ report: PlaybackSessionReport) {
        recordedCalls.withLock {
            $0.append(.progressed(report))
        }
    }

    func playbackStopped(_ report: PlaybackSessionReport) {
        recordedCalls.withLock {
            $0.append(.stopped(report))
        }
    }
}

@MainActor
private final class TrackSelectionRuntime: PlaybackRuntimeControlling {
    enum TestError: Error {
        case formatRejected
    }

    var productLifecycle: ProductPlaybackLifecycle = .idle
    var playbackPosition = PlaybackModel.PlaybackPosition(seconds: 0, duration: 600)
    var currentLaunchRequest: PlaybackLaunchRequest?
    var prefetchedMetadata: PlaybackMediaMetadata?
    var displayMediaProfile: PlaybackModel.MediaProfile?
    var displayFileSizeInBytes: Int64?
    var activeMediaFormatProvenance: MediaFormatProvenance = .source
    var effectiveMediaFormatInterpretation: EffectiveMediaFormatInterpretation {
        MediaFormatInterpretationResolver.resolve(
            source: SourceMediaFormatFact(
                contentKind: sourceVideoContentKind,
                projection: effectiveContentIsPanoramic ? .equirectangular180 : .flat,
                stereoLayout: .mono
            ),
            override: activeMediaFormatProvenance == .source ? nil : .standard
        )
    }
    var sourceVideoContentKind: PlaybackModel.SourceVideoContentKind = .rectilinear
    var sourceMediaFormatSummary = "Flat · Mono"
    var effectiveContentIsPanoramic = false
    var effectiveVideoFormatRevision: UInt64?
    var requestsSpatialVideoMode = false
    var activeSessionID: String?
    var actualPlaybackSeconds: Double = 0
    var didEndNaturally = false
    var lastErrorMessage: String?
    private(set) var observationGeneration: UInt64 = 0
    var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?
    var onPlaybackObservation: ((PlaybackRuntimeObservation) -> Void)?
    let availableAudioTracks: [PlaybackModel.AudioTrack]
    private(set) var currentAudioTrackID: String?
    let availableSubtitleTracks: [PlaybackModel.SubtitleTrack]
    private(set) var currentSubtitleTrackID: String?
    private var openCount = 0
    private(set) var lastStartTimeSeconds: Double?
    private(set) var formatApplicationCount = 0
    private(set) var sourceFormatApplicationCount = 0
    private(set) var lastAppliedFormat: MediaFormat?
    var nextFormatApplicationError: TestError?
    private var suspendsNextFormatApplication = false
    private var suspendedFormatApplicationContinuation: CheckedContinuation<Void, Never>?
    private var suspendsNextOpen = false
    private var suspendedOpenContinuation: CheckedContinuation<Void, Never>?

    init(
        audioTracks: [PlaybackModel.AudioTrack] = [],
        subtitleTracks: [PlaybackModel.SubtitleTrack] = []
    ) {
        self.availableAudioTracks = audioTracks
        self.currentAudioTrackID = audioTracks.first(where: \.isDefault)?.id ?? audioTracks.first?.id
        self.availableSubtitleTracks = subtitleTracks
        self.currentSubtitleTrackID = subtitleTracks.first(where: \.isDefault)?.id
    }

    func prepareForPlayback(_ request: PlaybackLaunchRequest) {
        if currentLaunchRequest == nil || currentLaunchRequest != request {
            observationGeneration &+= 1
        }
        currentLaunchRequest = request
        productLifecycle = .loading
        activeMediaFormatProvenance = .source
        lastAppliedFormat = nil
    }

    func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata) {
        prefetchedMetadata = metadata
    }

    func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double,
        initialSpeed: PlaybackModel.PlaybackSpeed,
        initialFormat: MediaFormat?
    ) async throws {
        currentLaunchRequest = request
        if suspendsNextOpen {
            suspendsNextOpen = false
            await withCheckedContinuation { continuation in
                suspendedOpenContinuation = continuation
            }
            try Task.checkCancellation()
        }
        activeSessionID = UUID().uuidString
        productLifecycle = .ready
        lastStartTimeSeconds = startTimeSeconds
        if let initialFormat {
            lastAppliedFormat = initialFormat
            activeMediaFormatProvenance = .userOverride
            formatApplicationCount += 1
        }
        openCount += 1
    }

    func setFormat(
        projection: PlaybackModel.ProjectionType,
        horizontalFieldOfViewDegrees: Int?,
        stereo: PlaybackModel.StereoLayout
    ) async throws {
        formatApplicationCount += 1
        if suspendsNextFormatApplication {
            suspendsNextFormatApplication = false
            await withCheckedContinuation { continuation in
                suspendedFormatApplicationContinuation = continuation
            }
        }
        if let error = nextFormatApplicationError {
            nextFormatApplicationError = nil
            throw error
        }
        lastAppliedFormat = MediaFormat(
            projection: Self.mediaProjection(from: projection),
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereoLayout: Self.mediaStereoLayout(from: stereo)
        )
        activeMediaFormatProvenance = .userOverride
    }

    func useSourceFormat() async throws {
        sourceFormatApplicationCount += 1
        lastAppliedFormat = nil
        activeMediaFormatProvenance = .source
    }

    func selectAudioTrack(_ track: PlaybackModel.AudioTrack) async throws {
        guard availableAudioTracks.contains(track) else { return }
        currentAudioTrackID = track.id
    }

    func selectSubtitleTrack(_ track: PlaybackModel.SubtitleTrack?) async throws {
        currentSubtitleTrackID = track?.id
    }

    func setSpeed(_ speed: PlaybackModel.PlaybackSpeed) {}
    func replay() {}

    func stop(releasingSourceAccess: Bool) {
        if currentLaunchRequest != nil {
            emitStopped()
        }
        productLifecycle = .idle
        currentLaunchRequest = nil
        activeSessionID = nil
    }

    func stopAndWait(releasingSourceAccess: Bool) async {
        stop(releasingSourceAccess: releasingSourceAccess)
    }

    func waitUntilOpened() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while openCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(openCount == 1)
    }

    func waitUntilConfigured() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while formatApplicationCount + sourceFormatApplicationCount == 0,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(openCount == 1)
        #expect(formatApplicationCount + sourceFormatApplicationCount == 1)
    }

    func waitUntilCurrentMediaIs(
        _ request: PlaybackLaunchRequest,
        replacing previousSessionID: String?
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while currentLaunchRequest != request || activeSessionID == previousSessionID,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(currentLaunchRequest == request)
        #expect(activeSessionID != previousSessionID)
    }

    func waitUntilConfigurationCountIs(_ expectedCount: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while formatApplicationCount + sourceFormatApplicationCount < expectedCount,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(formatApplicationCount + sourceFormatApplicationCount == expectedCount)
    }

    func suspendNextFormatApplication() {
        suspendsNextFormatApplication = true
    }

    func waitUntilFormatApplicationIsSuspended() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while suspendedFormatApplicationContinuation == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(suspendedFormatApplicationContinuation != nil)
    }

    func resumeSuspendedFormatApplication() {
        suspendedFormatApplicationContinuation?.resume()
        suspendedFormatApplicationContinuation = nil
    }

    func suspendNextOpen() {
        suspendsNextOpen = true
    }

    func waitUntilOpenIsSuspended() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while suspendedOpenContinuation == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(suspendedOpenContinuation != nil)
    }

    func resumeSuspendedOpen() {
        suspendedOpenContinuation?.resume()
        suspendedOpenContinuation = nil
    }

    func waitUntilCurrentRevisionIs(_ revision: String) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while currentLaunchRequest?.versionedIdentity?.contentRevision
                != .remote(entityTag: revision, sizeInBytes: 1_024),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(
            currentLaunchRequest?.versionedIdentity?.contentRevision
                == .remote(entityTag: revision, sizeInBytes: 1_024)
        )
    }

    func emitDiagnostics(
        positionSeconds: Double,
        actualPlaybackSeconds: Double,
        generation: UInt64? = nil
    ) {
        playbackPosition = .init(
            seconds: positionSeconds,
            duration: playbackPosition.duration
        )
        self.actualPlaybackSeconds = actualPlaybackSeconds
        emit(
            .diagnostics(
                position: playbackPosition,
                actualPlaybackSeconds: actualPlaybackSeconds
            ),
            generation: generation
        )
    }

    func emitLifecycle(
        _ lifecycle: ProductPlaybackLifecycle,
        positionSeconds: Double? = nil,
        generation: UInt64? = nil
    ) {
        productLifecycle = lifecycle
        if let positionSeconds {
            playbackPosition = .init(
                seconds: positionSeconds,
                duration: playbackPosition.duration
            )
        }
        emit(.lifecycle(lifecycle), generation: generation)
    }

    func emitSeekCompleted(positionSeconds: Double, generation: UInt64? = nil) {
        playbackPosition = .init(
            seconds: positionSeconds,
            duration: playbackPosition.duration
        )
        emit(.seekCompleted(positionSeconds: positionSeconds), generation: generation)
    }

    func emitStopped(generation: UInt64? = nil) {
        emit(.stopped, generation: generation)
    }

    func waitForAudioTrack(id: String) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while currentAudioTrackID != id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitForSubtitleTrack(id: String?) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while currentSubtitleTrackID != id, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func mediaProjection(
        from projection: PlaybackModel.ProjectionType
    ) -> MediaProjection {
        switch projection {
        case .flat: .flat
        case .equirectangular180: .equirectangular180
        case .equirectangular360: .equirectangular360
        case .customAngle: .customAngle
        }
    }

    private static func mediaStereoLayout(
        from stereoLayout: PlaybackModel.StereoLayout
    ) -> MediaStereoLayout {
        switch stereoLayout {
        case .mono, .multiview: .mono
        case .sideBySide: .sideBySide
        case .topBottom: .topBottom
        }
    }

    private func emit(
        _ event: PlaybackRuntimeObservation.Event,
        generation: UInt64?
    ) {
        onPlaybackObservation?(
            PlaybackRuntimeObservation(
                generation: generation ?? observationGeneration,
                event: event
            )
        )
    }
}
