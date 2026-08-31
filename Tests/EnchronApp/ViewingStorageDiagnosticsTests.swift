import Foundation
import MediaSource
import Playback
import XCTest
@testable import Enchron

#if DEBUG
nonisolated final class ViewingStorageDiagnosticsTests: XCTestCase {
    func testSnapshotEncodesOneClosedViewingAndStorageState() throws {
        let resumable = ViewingStateDiagnosticEntry(
            mediaIdentity: "sha256:" + String(repeating: "b", count: 64),
            contentRevision: "sha256:" + String(repeating: "2", count: 64),
            status: .resumable,
            positionSeconds: 120,
            durationSeconds: 3_600,
            completed: false
        )
        let completed = ViewingStateDiagnosticEntry(
            mediaIdentity: "sha256:" + String(repeating: "a", count: 64),
            contentRevision: "sha256:" + String(repeating: "1", count: 64),
            status: .completed,
            positionSeconds: 961,
            durationSeconds: 961,
            completed: true
        )
        let protectedMediaState = MediaStateProtectedDiagnosticEntry(
            mediaIdentity: resumable.mediaIdentity,
            contentRevision: resumable.contentRevision,
            formatPreference: .standard,
            playbackModePreference: .window,
            trackSelectionPreference: nil
        )
        let viewing = ViewingStateDiagnosticSnapshot(
            storeIdentity: "user-defaults:test",
            persistedRecordCount: 2,
            persistedBytes: 512,
            invalidRecordCount: 0,
            entries: [resumable, completed],
            protectedEntries: [protectedMediaState]
        )
        let container = ContainerIndexDebugSnapshot(
            cacheIdentity: "sha256:" + String(repeating: "c", count: 64),
            digest: "sha256:" + String(repeating: "d", count: 64),
            entries: [
                ContainerIndexDebugEntry(
                    contentRevision: resumable.contentRevision,
                    digest: "sha256:" + String(repeating: "e", count: 64),
                    bytes: 1_028,
                    contentLength: 10_000,
                    ranges: [
                        ContainerIndexDebugRange(
                            lowerBound: 0,
                            upperBoundExclusive: 1_024,
                            bytes: 1_024
                        )
                    ],
                    invalidFileCount: 0
                )
            ]
        )
        let artwork = ArtworkStoreDebugSnapshot(
            storeIdentity: "sha256:" + String(repeating: "f", count: 64),
            digest: "sha256:" + String(repeating: "0", count: 64),
            entries: [],
            invalidFileCount: 0
        )
        let containerIndexOpen = MediaByteStreamContainerIndexDebugSnapshot(
            scope: "media-byte-stream:open-2",
            contentRevision: resumable.contentRevision,
            containerIndexFinished: true,
            cacheHitRanges: [
                ContainerIndexDebugRange(
                    lowerBound: 1_024,
                    upperBoundExclusive: 2_048,
                    bytes: 1_024
                )
            ],
            sourceReadRanges: [
                ContainerIndexDebugRange(
                    lowerBound: 8_192,
                    upperBoundExclusive: 9_216,
                    bytes: 1_024
                )
            ],
            recordedRanges: []
        )
        let preferences = ViewingStorageDiagnosticSnapshot.ProtectedState.PlaybackPreferences(
            resumePolicy: "always-resume",
            endBehavior: "stop",
            defaultSpeed: 1,
            defaultEnvironmentID: nil,
            controlsAutoHideSeconds: 8
        )
        let folder = ViewingStorageDiagnosticSnapshot.ProtectedState.Folder(
            id: "folder-b",
            parentID: nil,
            name: "Folder"
        )
        let reference = ViewingStorageDiagnosticSnapshot.ProtectedState.Reference(
            id: "reference-a",
            folderID: folder.id,
            name: "fixture.mp4",
            sizeInBytes: 20_000
        )
        let protectedState = ViewingStorageDiagnosticSnapshot.ProtectedState(
            folders: [folder],
            references: [reference],
            playbackPreferences: preferences
        )
        let activePlayback = ViewingStorageDiagnosticSnapshot.ActivePlayback(
            sessionID: "session-1",
            mediaIdentity: resumable.mediaIdentity,
            contentRevision: resumable.contentRevision,
            viewingStateAuthority: "enchron-persistence",
            lifecycle: "playing",
            positionSeconds: 121,
            durationSeconds: 3_600,
            actualPlaybackSeconds: 16,
            endedNaturally: false
        )
        let snapshot = ViewingStorageDiagnosticSnapshot(
            viewingState: viewing,
            containerIndex: container,
            containerIndexOpen: containerIndexOpen,
            artwork: artwork,
            protectedState: protectedState,
            activePlayback: activePlayback
        )

        XCTAssertEqual(snapshot.schema, ViewingStorageDiagnosticSnapshot.schemaValue)
        XCTAssertEqual(snapshot.viewingState.viewingRecordCount, 2)
        XCTAssertEqual(snapshot.viewingState.resumableCount, 1)
        XCTAssertEqual(snapshot.viewingState.completedCount, 1)
        XCTAssertEqual(snapshot.viewingState.entries.map(\.mediaIdentity), [
            completed.mediaIdentity,
            resumable.mediaIdentity
        ])
        XCTAssertEqual(snapshot.containerIndex.totalBytes, 1_028)
        XCTAssertEqual(snapshot.containerIndex.entryCount, 1)
        XCTAssertEqual(snapshot.containerIndex.entries[0].ranges[0].upperBoundExclusive, 1_024)
        XCTAssertEqual(snapshot.containerIndexOpen, containerIndexOpen)
        XCTAssertEqual(snapshot.protectedState.references, [reference])
        XCTAssertEqual(snapshot.artwork.entryCount, 0)
        XCTAssertEqual(snapshot.activePlayback?.positionSeconds, 121)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
                as? [String: Any]
        )
        XCTAssertEqual(object["schema"] as? String, ViewingStorageDiagnosticSnapshot.schemaValue)
        let viewingObject = try XCTUnwrap(object["viewingState"] as? [String: Any])
        XCTAssertEqual(
            viewingObject["schema"] as? String,
            ViewingStateDiagnosticSnapshot.schemaValue
        )
        XCTAssertEqual(viewingObject["storeIdentity"] as? String, "user-defaults:test")
        let containerObject = try XCTUnwrap(object["containerIndex"] as? [String: Any])
        XCTAssertEqual(
            containerObject["schema"] as? String,
            ContainerIndexDebugSnapshot.schemaValue
        )
        XCTAssertEqual(containerObject["cacheIdentity"] as? String, container.cacheIdentity)
        let openObject = try XCTUnwrap(object["containerIndexOpen"] as? [String: Any])
        XCTAssertEqual(
            openObject["schema"] as? String,
            MediaByteStreamContainerIndexDebugSnapshot.schemaValue
        )
        XCTAssertEqual(openObject["scope"] as? String, containerIndexOpen.scope)
        XCTAssertEqual(
            openObject["contentRevision"] as? String,
            resumable.contentRevision
        )
        XCTAssertEqual(openObject["containerIndexFinished"] as? Bool, true)
        let artworkObject = try XCTUnwrap(object["artwork"] as? [String: Any])
        XCTAssertEqual(
            artworkObject["schema"] as? String,
            ArtworkStoreDebugSnapshot.schemaValue
        )
        XCTAssertEqual(artworkObject["storeIdentity"] as? String, artwork.storeIdentity)
        let protectedObject = try XCTUnwrap(object["protectedState"] as? [String: Any])
        XCTAssertEqual(
            protectedObject["schema"] as? String,
            ViewingStorageDiagnosticSnapshot.ProtectedState.schemaValue
        )
        XCTAssertEqual(protectedObject["digest"] as? String, protectedState.digest)
        let activeObject = try XCTUnwrap(object["activePlayback"] as? [String: Any])
        XCTAssertEqual(activeObject["mediaIdentity"] as? String, resumable.mediaIdentity)
        XCTAssertEqual(activeObject["contentRevision"] as? String, resumable.contentRevision)
    }

    func testProtectedStateDigestIsOrderIndependentAndValueSensitive() {
        let preferences = ViewingStorageDiagnosticSnapshot.ProtectedState.PlaybackPreferences(
            resumePolicy: "ask-every-time",
            endBehavior: "play-next",
            defaultSpeed: 1.5,
            defaultEnvironmentID: "moon",
            controlsAutoHideSeconds: 15
        )
        let folders = [
            ViewingStorageDiagnosticSnapshot.ProtectedState.Folder(
                id: "b",
                parentID: nil,
                name: "B"
            ),
            ViewingStorageDiagnosticSnapshot.ProtectedState.Folder(
                id: "a",
                parentID: nil,
                name: "A"
            )
        ]
        let references = [
            ViewingStorageDiagnosticSnapshot.ProtectedState.Reference(
                id: "2",
                folderID: "b",
                name: "two.mp4",
                sizeInBytes: 2
            ),
            ViewingStorageDiagnosticSnapshot.ProtectedState.Reference(
                id: "1",
                folderID: "a",
                name: "one.mp4",
                sizeInBytes: 1
            )
        ]

        let first = ViewingStorageDiagnosticSnapshot.ProtectedState(
            folders: folders,
            references: references,
            playbackPreferences: preferences
        )
        let reordered = ViewingStorageDiagnosticSnapshot.ProtectedState(
            folders: Array(folders.reversed()),
            references: Array(references.reversed()),
            playbackPreferences: preferences
        )
        let changed = ViewingStorageDiagnosticSnapshot.ProtectedState(
            folders: folders,
            references: references,
            playbackPreferences: .init(
                resumePolicy: preferences.resumePolicy,
                endBehavior: preferences.endBehavior,
                defaultSpeed: 2,
                defaultEnvironmentID: preferences.defaultEnvironmentID,
                controlsAutoHideSeconds: preferences.controlsAutoHideSeconds
            )
        )

        XCTAssertEqual(first, reordered)
        XCTAssertNotEqual(first.digest, changed.digest)
    }
}
#endif
