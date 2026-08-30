---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.clear-all-local-progress.o01@1",
  "title": "Clear All Local Progress",
  "criteria": [
    "The ordered transcript starts from an empty viewing-state baseline, plays viewing-storage-16m01s.mp4 beyond 20 seconds and Backs to create one resumable entry, then plays viewing-storage-16m01s-b.mp4 from positionMillionths 997000 through a natural Ended state and Backs to create a second, completed entry with positionSeconds equal to durationSeconds.",
    "relatedResults inline the pre-clear viewingStorageObservation from call 17. That snapshot.viewingState.entries contains exactly two records, one resumable and one completed, with distinct canonical identity/revision pairs, authority enchron-persistence, and invalidRecordCount zero. operation:storage.clear@1 then runs exactly for target playback-progress.",
    "The producer viewingStorageObservation.snapshot waits for viewing-state to become empty within deadlineSeconds 30 and reports zero viewing, resumable, and completed entries while preserving the same viewingState.storeIdentity and invalidRecordCount zero.",
    "relatedResults also inline the baseline, one-entry, and ended viewingStorageObservation objects from calls 01, 10, and 15. Across the inlined pre-clear snapshot and the producer snapshot, viewingState.protectedStateDigest, protectedEntries, protectedState.digest, folders, references, playbackPreferences, containerIndex cacheIdentity/digest/entries/totalBytes, and artwork storeIdentity/digest/entries/totalBytes are exactly unchanged."
  ],
  "negativeControls": [
    "Seed commands, fabricated records, card-marker inference, or a clear-action return without the inlined two-entry pre-clear snapshot and empty producer snapshot are inadmissible.",
    "Leaving either viewing class, clearing only one entry, changing protected library or preferences, changing either cache, changing a store identity, or introducing an invalid record violates the isolation contract.",
    "priorSnapshotDigests hashes without the inlined viewingStorageObservation objects cannot establish entry identity, resumable versus completed class, or disappearance of a record."
  ]
}
---
# Clear All Local Progress

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
