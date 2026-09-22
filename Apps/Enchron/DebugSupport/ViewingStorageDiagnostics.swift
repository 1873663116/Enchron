#if DEBUG
import CryptoKit
import Foundation
import MediaLibrary
import MediaSource
import Playback

nonisolated struct ViewingStorageDiagnosticSnapshot: Encodable, Equatable {
    static let schemaValue = "enchron.regression.viewing-storage-state@1"

    nonisolated struct ProtectedState: Encodable, Equatable {
        static let schemaValue = "enchron.regression.viewing-storage-protected-state@1"

        nonisolated struct Folder: Encodable, Equatable {
            let id: String
            let parentID: String?
            let name: String
        }

        nonisolated struct Reference: Encodable, Equatable {
            let id: String
            let folderID: String?
            let name: String
            let sizeInBytes: Int64
        }

        nonisolated struct PlaybackPreferences: Encodable, Equatable {
            let resumePolicy: String
            let endBehavior: String
            let defaultSpeed: Double
            let controlsAutoHideSeconds: Int
        }

        let schema: String
        let digest: String
        let folders: [Folder]
        let references: [Reference]
        let playbackPreferences: PlaybackPreferences

        @MainActor
        init(
            mediaLibrary: MediaLibraryViewModel,
            settings: SettingsViewModel
        ) {
            let folders = mediaLibrary.allFolders.map {
                Folder(
                    id: $0.id.uuidString.lowercased(),
                    parentID: $0.parentID?.uuidString.lowercased(),
                    name: $0.name
                )
            }
            .sorted { $0.id < $1.id }
            let library = mediaLibrary.library
            let references = (
                library.references(in: nil).map { (nil, $0) }
                    + mediaLibrary.allFolders.flatMap { folder in
                        library.references(in: folder.id).map { (folder.id, $0) }
                    }
            )
            .map { folderID, reference in
                Reference(
                    id: reference.id.uuidString.lowercased(),
                    folderID: folderID?.uuidString.lowercased(),
                    name: reference.name,
                    sizeInBytes: reference.sizeInBytes
                )
            }
            .sorted { $0.id < $1.id }
            let playbackPreferences = PlaybackPreferences(settings.preferences)

            self.schema = Self.schemaValue
            self.digest = Self.digest(
                folders: folders,
                references: references,
                playbackPreferences: playbackPreferences
            )
            self.folders = folders
            self.references = references
            self.playbackPreferences = playbackPreferences
        }

        init(
            folders: [Folder],
            references: [Reference],
            playbackPreferences: PlaybackPreferences
        ) {
            let folders = folders.sorted { $0.id < $1.id }
            let references = references.sorted { $0.id < $1.id }
            self.schema = Self.schemaValue
            self.digest = Self.digest(
                folders: folders,
                references: references,
                playbackPreferences: playbackPreferences
            )
            self.folders = folders
            self.references = references
            self.playbackPreferences = playbackPreferences
        }

        private static func digest(
            folders: [Folder],
            references: [Reference],
            playbackPreferences: PlaybackPreferences
        ) -> String {
            nonisolated struct Payload: Encodable {
                let folders: [Folder]
                let references: [Reference]
                let playbackPreferences: PlaybackPreferences
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(Payload(
                folders: folders,
                references: references,
                playbackPreferences: playbackPreferences
            ))) ?? Data()
            return "sha256:" + SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    nonisolated struct ActivePlayback: Encodable, Equatable {
        let sessionID: String?
        let mediaIdentity: String?
        let contentRevision: String?
        let viewingStateAuthority: String
        let lifecycle: String
        let positionSeconds: Double
        let durationSeconds: Double
        let actualPlaybackSeconds: Double
        let endedNaturally: Bool

        @MainActor
        init(runtime: PlaybackRuntime, request: PlaybackLaunchRequest) {
            self.sessionID = runtime.activeSessionID
            self.mediaIdentity = request.versionedIdentity.map {
                "sha256:" + $0.mediaIdentity.storageKey
            }
            self.contentRevision = request.versionedIdentity.map {
                "sha256:" + $0.contentRevision.storageKey
            }
            self.viewingStateAuthority = switch request.viewingStateAuthority {
            case .enchronPersistence: "enchron-persistence"
            case .mediaServer: "media-server"
            }
            self.lifecycle = runtime.productLifecycle.rawValue
            self.positionSeconds = runtime.playbackPosition.seconds
            self.durationSeconds = runtime.playbackPosition.duration
            self.actualPlaybackSeconds = runtime.actualPlaybackSeconds
            self.endedNaturally = runtime.didEndNaturally
        }

        init(
            sessionID: String?,
            mediaIdentity: String?,
            contentRevision: String?,
            viewingStateAuthority: String,
            lifecycle: String,
            positionSeconds: Double,
            durationSeconds: Double,
            actualPlaybackSeconds: Double,
            endedNaturally: Bool
        ) {
            self.sessionID = sessionID
            self.mediaIdentity = mediaIdentity
            self.contentRevision = contentRevision
            self.viewingStateAuthority = viewingStateAuthority
            self.lifecycle = lifecycle
            self.positionSeconds = positionSeconds
            self.durationSeconds = durationSeconds
            self.actualPlaybackSeconds = actualPlaybackSeconds
            self.endedNaturally = endedNaturally
        }
    }

    let schema: String
    let viewingState: ViewingStateDiagnosticSnapshot
    let containerIndex: ContainerIndexDebugSnapshot
    let containerIndexOpen: MediaByteStreamContainerIndexDebugSnapshot?
    let artwork: ArtworkStoreDebugSnapshot
    let protectedState: ProtectedState
    let activePlayback: ActivePlayback?

    @MainActor
    init(
        viewingState: ViewingStateDiagnosticSnapshot,
        containerIndex: ContainerIndexDebugSnapshot,
        artwork: ArtworkStoreDebugSnapshot,
        mediaLibrary: MediaLibraryViewModel,
        settings: SettingsViewModel,
        playbackRuntime: PlaybackRuntime
    ) {
        self.schema = Self.schemaValue
        self.viewingState = viewingState
        self.containerIndex = containerIndex
        self.containerIndexOpen = playbackRuntime
            .debugCurrentByteStreamCounters()?
            .containerIndexOpen
        self.artwork = artwork
        self.protectedState = ProtectedState(
            mediaLibrary: mediaLibrary,
            settings: settings
        )
        self.activePlayback = playbackRuntime.currentLaunchRequest.map {
            ActivePlayback(runtime: playbackRuntime, request: $0)
        }
    }

    init(
        viewingState: ViewingStateDiagnosticSnapshot,
        containerIndex: ContainerIndexDebugSnapshot,
        containerIndexOpen: MediaByteStreamContainerIndexDebugSnapshot?,
        artwork: ArtworkStoreDebugSnapshot,
        protectedState: ProtectedState,
        activePlayback: ActivePlayback?
    ) {
        self.schema = Self.schemaValue
        self.viewingState = viewingState
        self.containerIndex = containerIndex
        self.containerIndexOpen = containerIndexOpen
        self.artwork = artwork
        self.protectedState = protectedState
        self.activePlayback = activePlayback
    }
}

private extension ViewingStorageDiagnosticSnapshot.ProtectedState.PlaybackPreferences {
    init(_ preferences: UserPreferences) {
        self.resumePolicy = switch preferences.resumePolicy {
        case .askEveryTime: "ask-every-time"
        case .alwaysResume: "always-resume"
        case .alwaysStartFromBeginning: "always-start-from-beginning"
        }
        self.endBehavior = switch preferences.playbackEndBehavior {
        case .repeatOne: "repeat-one"
        case .playNext: "play-next"
        }
        self.defaultSpeed = preferences.defaultPlaybackSpeed
        self.controlsAutoHideSeconds = preferences.controlsAutoHideSeconds
    }
}
#endif
