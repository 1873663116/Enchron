import Foundation
import MediaSource
import PlaybackFeature
import Testing

@MainActor
struct TrackSelectionPreferenceTests {
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

    private static func request(revision: String) -> PlaybackLaunchRequest {
        let identity = VersionedMediaIdentity(
            mediaIdentity: .remote(sourceKey: "test-source", canonicalPath: "/Movie.mkv"),
            contentRevision: .remote(entityTag: revision, sizeInBytes: 1_024)
        )
        return PlaybackLaunchRequest(
            url: URL(string: "https://example.invalid/Movie.mkv")!,
            displayName: "Movie.mkv",
            versionedIdentity: identity
        )
    }
}

private struct StartFromBeginningPreferences: PlaybackPreferencesProviding {
    func loadPlaybackPreferences() -> PlaybackPreferences {
        PlaybackPreferences(resumePolicy: .alwaysStartFromBeginning)
    }
}

@MainActor
private final class TrackSelectionRuntime: PlaybackRuntimeControlling {
    var productLifecycle: ProductPlaybackLifecycle = .idle
    var playbackPosition = PlaybackModel.PlaybackPosition(seconds: 0, duration: 600)
    var currentLaunchRequest: PlaybackLaunchRequest?
    var prefetchedMetadata: PlaybackMediaMetadata?
    var displayMediaProfile: PlaybackModel.MediaProfile?
    var displayFileSizeInBytes: Int64?
    var activeSessionID: String?
    var actualPlaybackSeconds: Double = 0
    var didEndNaturally = false
    var lastErrorMessage: String?
    var onMediaProfileResolved: ((PlaybackLaunchRequest, PlaybackModel.MediaProfile) -> Void)?
    let availableAudioTracks: [PlaybackModel.AudioTrack]
    private(set) var currentAudioTrackID: String?
    let availableSubtitleTracks: [PlaybackModel.SubtitleTrack]
    private(set) var currentSubtitleTrackID: String?
    private var openCount = 0
    private var formatApplicationCount = 0

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
        currentLaunchRequest = request
        productLifecycle = .loading
    }

    func applyPrefetchedMetadata(_ metadata: PlaybackMediaMetadata) {
        prefetchedMetadata = metadata
    }

    func open(
        _ request: PlaybackLaunchRequest,
        startTimeSeconds: Double,
        initialSpeed: PlaybackModel.PlaybackSpeed
    ) async throws {
        currentLaunchRequest = request
        activeSessionID = UUID().uuidString
        productLifecycle = .ready
        openCount += 1
    }

    func setFormat(
        projection: PlaybackModel.ProjectionType,
        stereo: PlaybackModel.StereoLayout
    ) async throws {
        formatApplicationCount += 1
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
        while formatApplicationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(openCount == 1)
        #expect(formatApplicationCount == 1)
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
}
