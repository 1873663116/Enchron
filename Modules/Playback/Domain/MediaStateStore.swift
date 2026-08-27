import Foundation
import MediaSource

nonisolated public enum PersistedPlaybackMode: String, Codable, Equatable, Sendable {
    case window
    case panorama
}

nonisolated package struct PersistedMediaState: Codable, Equatable, Sendable {
    package let versionedIdentity: VersionedMediaIdentity
    package var viewingStatus: ViewingStatus?
    package var formatPreference: MediaFormat?
    package var playbackModePreference: PersistedPlaybackMode?
    package var trackSelectionPreference: TrackSelectionPreference?

    package init(
        versionedIdentity: VersionedMediaIdentity,
        viewingStatus: ViewingStatus? = nil,
        formatPreference: MediaFormat? = nil,
        playbackModePreference: PersistedPlaybackMode? = nil,
        trackSelectionPreference: TrackSelectionPreference? = nil
    ) {
        self.versionedIdentity = versionedIdentity
        self.viewingStatus = viewingStatus
        self.formatPreference = formatPreference
        self.playbackModePreference = playbackModePreference
        self.trackSelectionPreference = trackSelectionPreference
    }
}

nonisolated package struct PersistedPlaybackPresentationPreferences: Equatable, Sendable {
    package let format: MediaFormat?
    package let playbackMode: PersistedPlaybackMode?
}

package actor MediaStateStore {
    private let defaults: UserDefaults
    private let keyPrefix = "enchron.media-state.v1."

    package init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    package func loadValidated(
        for identity: VersionedMediaIdentity
    ) -> PersistedMediaState? {
        let key = storageKey(for: identity.mediaIdentity)
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(PersistedMediaState.self, from: data) else {
            return nil
        }
        guard state.versionedIdentity.contentRevision == identity.contentRevision else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return state
    }

    package func loadPlaybackPresentationPreferencesValidated(
        for identity: VersionedMediaIdentity
    ) -> PersistedPlaybackPresentationPreferences? {
        guard let state = loadValidated(for: identity) else { return nil }
        return PersistedPlaybackPresentationPreferences(
            format: state.formatPreference,
            playbackMode: state.playbackModePreference
        )
    }

    package func viewingProjection(for identity: MediaIdentity) -> ViewingStatus? {
        let key = storageKey(for: identity)
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(PersistedMediaState.self, from: data) else {
            return nil
        }
        return state.viewingStatus
    }

    package func applyViewingMutation(
        _ mutation: ViewingStateMutation,
        for identity: VersionedMediaIdentity
    ) {
        var state = loadValidated(for: identity) ?? PersistedMediaState(versionedIdentity: identity)
        switch mutation {
        case .unchanged:
            return
        case .remove:
            state.viewingStatus = nil
        case .save(let status):
            state.viewingStatus = status
        }
        saveOrRemoveEmpty(state)
    }

    package func saveFormat(_ format: MediaFormat, for identity: VersionedMediaIdentity) {
        var state = loadValidated(for: identity) ?? PersistedMediaState(versionedIdentity: identity)
        state.formatPreference = format
        saveOrRemoveEmpty(state)
    }

    package func resetFormat(for identity: VersionedMediaIdentity) {
        var state = loadValidated(for: identity) ?? PersistedMediaState(versionedIdentity: identity)
        state.formatPreference = nil
        saveOrRemoveEmpty(state)
    }

    package func savePlaybackMode(
        _ mode: PersistedPlaybackMode,
        for identity: VersionedMediaIdentity
    ) {
        var state = loadValidated(for: identity) ?? PersistedMediaState(versionedIdentity: identity)
        state.playbackModePreference = mode
        saveOrRemoveEmpty(state)
    }

    package func saveAudioTrackSelection(
        id: String,
        for identity: VersionedMediaIdentity
    ) {
        var state = loadValidated(for: identity) ?? PersistedMediaState(versionedIdentity: identity)
        var preference = state.trackSelectionPreference ?? TrackSelectionPreference()
        preference.audioTrackID = id
        state.trackSelectionPreference = preference
        saveOrRemoveEmpty(state)
    }

    package func saveSubtitleTrackSelection(
        _ selection: SubtitleTrackSelectionPreference,
        for identity: VersionedMediaIdentity
    ) {
        var state = loadValidated(for: identity) ?? PersistedMediaState(versionedIdentity: identity)
        var preference = state.trackSelectionPreference ?? TrackSelectionPreference()
        preference.subtitleTrack = selection
        state.trackSelectionPreference = preference
        saveOrRemoveEmpty(state)
    }

    package func clearViewingStates() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            guard let data = defaults.data(forKey: key),
                  var state = try? JSONDecoder().decode(PersistedMediaState.self, from: data) else {
                defaults.removeObject(forKey: key)
                continue
            }
            state.viewingStatus = nil
            saveOrRemoveEmpty(state)
        }
    }

    private func saveOrRemoveEmpty(_ state: PersistedMediaState) {
        let key = storageKey(for: state.versionedIdentity.mediaIdentity)
        guard state.viewingStatus != nil
            || state.formatPreference != nil
            || state.playbackModePreference != nil
            || state.trackSelectionPreference != nil else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    private func storageKey(for identity: MediaIdentity) -> String {
        keyPrefix + identity.storageKey
    }
}
