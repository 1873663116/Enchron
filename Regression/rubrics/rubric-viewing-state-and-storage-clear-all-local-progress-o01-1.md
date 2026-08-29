---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.clear-all-local-progress.o01@1",
  "title": "Clear All Local Progress",
  "criteria": [
    "The transcript starts with zero viewing entries, plays viewing-storage-16m01s.mp4 beyond 20 seconds and exits to create exactly one resumable entry, then plays viewing-storage-16m01s-b.mp4 from positionMillionths 997000 through a natural Ended state and exits to create a second, completed entry with positionSeconds equal to durationSeconds.",
    "The snapshot immediately before clearing has exactly two viewing entries, one resumable and one completed, with distinct canonical identity/revision pairs, authority enchron-persistence, and invalidRecordCount zero; operation:storage.clear@1 is then invoked exactly for target playback-progress.",
    "The final probe waits for viewing-state to become empty within deadlineSeconds 30 and reports zero viewing, resumable, and completed entries while preserving the same viewingState.storeIdentity and invalidRecordCount zero.",
    "Across the before-clear and final snapshots, viewingState.protectedStateDigest, protectedEntries, protectedState.digest, folders, references, playbackPreferences, containerIndex cacheIdentity/digest/entries/totalBytes, and artwork storeIdentity/digest/entries/totalBytes are exactly unchanged; the final observation binds every prior scenario snapshot digest."
  ],
  "negativeControls": [
    "Seed commands, fabricated records, card-marker inference, or a clear-action return without the real two-entry before snapshot and empty final snapshot are inadmissible.",
    "Leaving either viewing class, clearing only one entry, changing protected library or preferences, changing either cache, changing a store identity, or introducing an invalid record violates the isolation contract."
  ]
}
---
# Clear All Local Progress

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
