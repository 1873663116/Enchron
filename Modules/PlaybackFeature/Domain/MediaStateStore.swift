import Foundation
import MediaSource

package struct PersistedMediaState: Codable, Equatable, Sendable {
    package let versionedIdentity: VersionedMediaIdentity
    package var viewingStatus: ViewingStatus?
    package var formatPreference: MediaFormat?

    package init(
        versionedIdentity: VersionedMediaIdentity,
        viewingStatus: ViewingStatus? = nil,
        formatPreference: MediaFormat? = nil
    ) {
        self.versionedIdentity = versionedIdentity
        self.viewingStatus = viewingStatus
        self.formatPreference = formatPreference
    }
}

package actor MediaStateStore {
    private let defaults: UserDefaults
    private let keyPrefix = "enchron.media-state.v1."

    package init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Opening-time read that validates the current content revision and removes
    /// state that belongs to replaced media bytes.
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

    /// Returns the last known viewing state for browser decoration without
    /// validating or mutating the stored content revision. Revision validation
    /// remains an opening-time responsibility of `loadValidated(for:)`.
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
        guard state.viewingStatus != nil || state.formatPreference != nil else {
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
