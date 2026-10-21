---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.exit-saves-position.o01@1",
  "title": "Exit Saves Position",
  "criteria": [
    "The ordered transcript opens MediaLibrary-grid-video-viewing-storage-16m01s.mp4 from a baseline whose viewingState has zero viewing, resumable, completed, and invalid records. Playback then reaches at least 20 seconds with at least 300 seconds remaining before the pre-exit viewing-storage snapshot and the real PlayerUI-InfoBar-button-back action.",
    "relatedResults inline the pre-exit viewingStorageObservation from call 08. That snapshot has one activePlayback with viewingStateAuthority enchron-persistence, lifecycle playing, endedNaturally false, a non-none sessionID, canonical mediaIdentity and contentRevision, positionSeconds at least 20, and durationSeconds minus positionSeconds at least 300.",
    "The producer snapshot has no activePlayback and exactly one resumable, non-completed viewing entry whose mediaIdentity and contentRevision equal the inlined pre-exit activePlayback, whose authority is enchron-persistence, and whose positionSeconds differs from the inlined pre-exit positionSeconds by no more than 5 seconds. invalidRecordCount remains zero.",
    "relatedResults also inline the empty baseline snapshot from call 01. The baseline, pre-exit, and producer snapshots share one unchanged viewingState.storeIdentity."
  ],
  "negativeControls": [
    "A wait-position receipt or Back action without the inlined baseline, pre-exit, and producer viewingStorageObservation snapshots is inadmissible; an unavailable required field or unresolved result binding is Indeterminate.",
    "A short or near-end playback, changed media identity or content revision, completed rather than resumable state, more than five seconds of persistence drift, a remaining activePlayback, a changed store identity, or any invalid record violates the contract.",
    "priorSnapshotDigests hashes without the inlined pre-exit viewingStorageObservation cannot exhibit activePlayback fields or the persisted entry contents."
  ]
}
---
# Exit Saves Position

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
