import Foundation
import MediaSource
#if DEBUG
import CryptoKit
#endif

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

#if DEBUG
nonisolated public struct ViewingStateDiagnosticEntry: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case resumable
        case completed
    }

    public enum Authority: String, Codable, Equatable, Sendable {
        case enchronPersistence = "enchron-persistence"
    }

    public let mediaIdentity: String
    public let contentRevision: String
    public let authority: Authority
    public let status: Status
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let completed: Bool

    public init(
        mediaIdentity: String,
        contentRevision: String,
        authority: Authority = .enchronPersistence,
        status: Status,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool
    ) {
        self.mediaIdentity = mediaIdentity
        self.contentRevision = contentRevision
        self.authority = authority
        self.status = status
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.completed = completed
    }
}

nonisolated public struct MediaStateProtectedDiagnosticEntry: Codable, Equatable, Sendable {
    public let mediaIdentity: String
    public let contentRevision: String
    public let formatPreference: MediaFormat?
    public let playbackModePreference: PersistedPlaybackMode?
    public let trackSelectionPreference: TrackSelectionPreference?

    public init(
        mediaIdentity: String,
        contentRevision: String,
        formatPreference: MediaFormat?,
        playbackModePreference: PersistedPlaybackMode?,
        trackSelectionPreference: TrackSelectionPreference?
    ) {
        self.mediaIdentity = mediaIdentity
        self.contentRevision = contentRevision
        self.formatPreference = formatPreference
        self.playbackModePreference = playbackModePreference
        self.trackSelectionPreference = trackSelectionPreference
    }
}

nonisolated public struct ViewingStateDiagnosticSnapshot: Codable, Equatable, Sendable {
    public static let schemaValue = "enchron.regression.viewing-state-store@1"

    public let schema: String
    public let storeIdentity: String
    public let persistedRecordCount: Int
    public let persistedBytes: Int64
    public let invalidRecordCount: Int
    public let viewingRecordCount: Int
    public let resumableCount: Int
    public let completedCount: Int
    public let entries: [ViewingStateDiagnosticEntry]
    public let protectedStateDigest: String
    public let protectedEntries: [MediaStateProtectedDiagnosticEntry]

    public init(
        storeIdentity: String,
        persistedRecordCount: Int,
        persistedBytes: Int64,
        invalidRecordCount: Int,
        entries: [ViewingStateDiagnosticEntry],
        protectedEntries: [MediaStateProtectedDiagnosticEntry]
    ) {
        let orderedEntries = entries.sorted {
            ($0.mediaIdentity, $0.contentRevision)
                < ($1.mediaIdentity, $1.contentRevision)
        }
        let orderedProtectedEntries = protectedEntries.sorted {
            ($0.mediaIdentity, $0.contentRevision)
                < ($1.mediaIdentity, $1.contentRevision)
        }
        self.schema = Self.schemaValue
        self.storeIdentity = storeIdentity
        self.persistedRecordCount = persistedRecordCount
        self.persistedBytes = persistedBytes
        self.invalidRecordCount = invalidRecordCount
        self.viewingRecordCount = orderedEntries.count
        self.resumableCount = orderedEntries.filter { $0.completed == false }.count
        self.completedCount = orderedEntries.filter(\.completed).count
        self.entries = orderedEntries
        self.protectedStateDigest = Self.digest(orderedProtectedEntries)
        self.protectedEntries = orderedProtectedEntries
    }

    package init(
        storeIdentity: String,
        states: [PersistedMediaState],
        persistedBytes: Int64,
        invalidRecordCount: Int
    ) {
        let entries = states.compactMap { state -> ViewingStateDiagnosticEntry? in
            guard let viewingStatus = state.viewingStatus else { return nil }
            let identity = "sha256:" + state.versionedIdentity.mediaIdentity.storageKey
            let revision = "sha256:" + state.versionedIdentity.contentRevision.storageKey
            switch viewingStatus {
            case .resumable(let positionSeconds, let durationSeconds):
                return ViewingStateDiagnosticEntry(
                    mediaIdentity: identity,
                    contentRevision: revision,
                    status: .resumable,
                    positionSeconds: positionSeconds,
                    durationSeconds: durationSeconds,
                    completed: false
                )
            case .completed(let durationSeconds):
                return ViewingStateDiagnosticEntry(
                    mediaIdentity: identity,
                    contentRevision: revision,
                    status: .completed,
                    positionSeconds: durationSeconds,
                    durationSeconds: durationSeconds,
                    completed: true
                )
            }
        }
        let protectedEntries = states.compactMap {
            state -> MediaStateProtectedDiagnosticEntry? in
            guard state.formatPreference != nil
                || state.playbackModePreference != nil
                || state.trackSelectionPreference != nil else { return nil }
            return MediaStateProtectedDiagnosticEntry(
                mediaIdentity: "sha256:" + state.versionedIdentity.mediaIdentity.storageKey,
                contentRevision: "sha256:"
                    + state.versionedIdentity.contentRevision.storageKey,
                formatPreference: state.formatPreference,
                playbackModePreference: state.playbackModePreference,
                trackSelectionPreference: state.trackSelectionPreference
            )
        }
        self.init(
            storeIdentity: storeIdentity,
            persistedRecordCount: states.count,
            persistedBytes: persistedBytes,
            invalidRecordCount: invalidRecordCount,
            entries: entries,
            protectedEntries: protectedEntries
        )
    }

    private static func digest(
        _ entries: [MediaStateProtectedDiagnosticEntry]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(entries)) ?? Data()
        return "sha256:" + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
#endif

package actor MediaStateStore {
    private let defaults: UserDefaults
    private let keyPrefix = "enchron.media-state.v1."
    #if DEBUG
    private let diagnosticStoreIdentity: String
    #endif

    package init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        #if DEBUG
        self.diagnosticStoreIdentity = "user-defaults:" + (suiteName ?? "standard")
        #endif
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

    #if DEBUG
    package func debugSnapshot() -> ViewingStateDiagnosticSnapshot {
        var states: [PersistedMediaState] = []
        var persistedBytes: Int64 = 0
        var invalidRecordCount = 0
        for key in defaults.dictionaryRepresentation().keys
            .filter({ $0.hasPrefix(keyPrefix) })
            .sorted() {
            guard let data = defaults.data(forKey: key) else {
                invalidRecordCount += 1
                continue
            }
            persistedBytes += Int64(data.count)
            guard let state = try? JSONDecoder().decode(
                PersistedMediaState.self,
                from: data
            ), key == storageKey(for: state.versionedIdentity.mediaIdentity) else {
                invalidRecordCount += 1
                continue
            }
            states.append(state)
        }
        return ViewingStateDiagnosticSnapshot(
            storeIdentity: diagnosticStoreIdentity,
            states: states,
            persistedBytes: persistedBytes,
            invalidRecordCount: invalidRecordCount
        )
    }
    #endif

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
