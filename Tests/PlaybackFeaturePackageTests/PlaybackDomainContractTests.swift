import Foundation
import MediaSource
import Testing
@testable import Playback

@MainActor
struct PlaybackDomainContractTests {
    @Test("viewing state policy answers every session evidence shape")
    func viewingStatePolicyAnswersEverySessionEvidenceShape() {
        let unknownDuration = PlaybackSessionEvidence(
            durationSeconds: 0,
            positionSeconds: 0,
            actualPlaybackSeconds: 30,
            endedNaturally: false
        )
        #expect(
            ViewingStatePolicy.mutation(for: unknownDuration) == .unchanged,
            "evidence without a duration must leave the saved viewing state alone"
        )

        let shortInteraction = PlaybackSessionEvidence(
            durationSeconds: 3_600,
            positionSeconds: 120,
            actualPlaybackSeconds: 14.9,
            endedNaturally: false
        )
        #expect(
            ViewingStatePolicy.mutation(for: shortInteraction) == .unchanged,
            "a short interaction must not overwrite viewing state"
        )

        let resume = PlaybackSessionEvidence(
            durationSeconds: 3_600,
            positionSeconds: 1_800,
            actualPlaybackSeconds: 30,
            endedNaturally: false
        )
        #expect(
            ViewingStatePolicy.mutation(for: resume)
                == .save(.resumable(positionSeconds: 1_800, durationSeconds: 3_600)),
            "an eligible early exit must save a resume position"
        )

        let nearEnd = PlaybackSessionEvidence(
            durationSeconds: 3_600,
            positionSeconds: 3_300,
            actualPlaybackSeconds: 30,
            endedNaturally: false
        )
        #expect(
            ViewingStatePolicy.mutation(for: nearEnd) == .remove,
            "an early exit inside the near-end boundary must not remain resumable"
        )

        let naturalEnd = PlaybackSessionEvidence(
            durationSeconds: 900,
            positionSeconds: 900,
            actualPlaybackSeconds: 15,
            endedNaturally: true
        )
        #expect(
            ViewingStatePolicy.mutation(for: naturalEnd) == .save(.completed(durationSeconds: 900)),
            "only a natural end may persist completed state"
        )
    }

    @Test("stop end behaviour resolves to no automatic action")
    func stopEndBehaviourResolvesToNoAutomaticAction() {
        #expect(
            PlaybackEndPolicy.action(for: .stop) == .stayEnded,
            "Stop end behavior must retain the ended session without an automatic action"
        )
    }

    @Test("custom angle normalization snaps its field of view")
    func customAngleNormalizationSnapsItsFieldOfView() {
        let normalizedCustomAngle = MediaFormatPolicy.normalized(
            MediaFormat(
                projection: .customAngle,
                horizontalFieldOfViewDegrees: 237,
                stereoLayout: .mono
            )
        )

        #expect(
            normalizedCustomAngle.horizontalFieldOfViewDegrees == 240,
            "Custom Angle must snap to a supported ten-degree increment"
        )
    }

    @Test("media state store keys viewing state and format by content revision")
    func mediaStateStoreKeysViewingStateAndFormatByContentRevision() async throws {
        let suiteName = "app.scenicOne.domain-checks.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panoramicFormat = MediaFormat(projection: .equirectangular360, stereoLayout: .mono)
        let mediaIdentity = MediaIdentity.local(resourceIdentifier: Data([0x01]))
        let originalVersion = VersionedMediaIdentity(
            mediaIdentity: mediaIdentity,
            contentRevision: .file(
                resourceIdentifier: Data([0x01]),
                sizeInBytes: 1_000,
                modifiedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let replacementVersion = VersionedMediaIdentity(
            mediaIdentity: mediaIdentity,
            contentRevision: .file(
                resourceIdentifier: Data([0x01]),
                sizeInBytes: 2_000,
                modifiedAt: Date(timeIntervalSince1970: 200)
            )
        )
        let stateStore = MediaStateStore(suiteName: suiteName)

        await stateStore.applyViewingMutation(
            .save(.resumable(positionSeconds: 120, durationSeconds: 3_600)),
            for: originalVersion
        )
        await stateStore.saveFormat(panoramicFormat, for: originalVersion)
        let storedOriginal = await stateStore.loadValidated(for: originalVersion)
        #expect(
            storedOriginal?.viewingStatus
                == .resumable(positionSeconds: 120, durationSeconds: 3_600),
            "viewing state and format must share the versioned media key"
        )

        await stateStore.applyViewingMutation(.remove, for: originalVersion)
        let stateAfterStartOver = await stateStore.loadValidated(for: originalVersion)
        #expect(
            stateAfterStartOver?.viewingStatus == nil
                && stateAfterStartOver?.formatPreference == panoramicFormat,
            "Start Over must clear viewing state without discarding media format"
        )

        await stateStore.applyViewingMutation(
            .save(.resumable(positionSeconds: 120, durationSeconds: 3_600)),
            for: originalVersion
        )
        let browserProjection = await stateStore.viewingProjection(for: mediaIdentity)
        #expect(
            browserProjection == .resumable(positionSeconds: 120, durationSeconds: 3_600),
            "browser projection must read last-known viewing state without revision validation"
        )

        #if DEBUG
        let completedIdentity = MediaIdentity.local(resourceIdentifier: Data([0x02]))
        let completedVersion = VersionedMediaIdentity(
            mediaIdentity: completedIdentity,
            contentRevision: .file(
                resourceIdentifier: Data([0x02]),
                sizeInBytes: 961,
                modifiedAt: Date(timeIntervalSince1970: 300)
            )
        )
        await stateStore.applyViewingMutation(
            .save(.completed(durationSeconds: 961)),
            for: completedVersion
        )
        let beforeClear = await stateStore.debugSnapshot()
        #expect(beforeClear.schema == ViewingStateDiagnosticSnapshot.schemaValue)
        #expect(beforeClear.persistedRecordCount == 2)
        #expect(beforeClear.viewingRecordCount == 2)
        #expect(beforeClear.resumableCount == 1)
        #expect(beforeClear.completedCount == 1)
        #expect(beforeClear.invalidRecordCount == 0)
        #expect(beforeClear.entries.contains(
            ViewingStateDiagnosticEntry(
                mediaIdentity: "sha256:\(mediaIdentity.storageKey)",
                contentRevision: "sha256:\(originalVersion.contentRevision.storageKey)",
                status: .resumable,
                positionSeconds: 120,
                durationSeconds: 3_600,
                completed: false
            )
        ))
        #expect(beforeClear.entries.contains(
            ViewingStateDiagnosticEntry(
                mediaIdentity: "sha256:\(completedIdentity.storageKey)",
                contentRevision: "sha256:\(completedVersion.contentRevision.storageKey)",
                status: .completed,
                positionSeconds: 961,
                durationSeconds: 961,
                completed: true
            )
        ))
        #expect(beforeClear.protectedEntries.count == 1)

        await stateStore.clearViewingStates()
        let afterClear = await stateStore.debugSnapshot()
        #expect(afterClear.storeIdentity == beforeClear.storeIdentity)
        #expect(afterClear.persistedRecordCount == 1)
        #expect(afterClear.viewingRecordCount == 0)
        #expect(afterClear.resumableCount == 0)
        #expect(afterClear.completedCount == 0)
        #expect(afterClear.protectedEntries == beforeClear.protectedEntries)
        #expect(afterClear.protectedStateDigest == beforeClear.protectedStateDigest)
        #endif

        let storedReplacement = await stateStore.loadValidated(for: replacementVersion)
        #expect(
            storedReplacement == nil,
            "a changed Content Revision must invalidate persisted media state"
        )
    }

    @Test("actual playback accumulation discounts seek discontinuities")
    func actualPlaybackAccumulationDiscountsSeekDiscontinuities() {
        var accumulator = ActualPlaybackAccumulator()
        let observationStart = Date(timeIntervalSince1970: 100)
        accumulator.record(
            positionSeconds: 10,
            at: observationStart,
            isPlaying: true,
            playbackRate: 1
        )
        accumulator.record(
            positionSeconds: 11,
            at: observationStart.addingTimeInterval(1),
            isPlaying: true,
            playbackRate: 1
        )
        accumulator.markDiscontinuity()
        accumulator.record(
            positionSeconds: 3_000,
            at: observationStart.addingTimeInterval(2),
            isPlaying: true,
            playbackRate: 1
        )
        accumulator.record(
            positionSeconds: 3_001,
            at: observationStart.addingTimeInterval(3),
            isPlaying: true,
            playbackRate: 1
        )

        #expect(
            abs(accumulator.seconds - 2) < 0.001,
            "a seek discontinuity must not count skipped media as actual playback"
        )
    }
}
