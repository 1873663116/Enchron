---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.exit-saves-position.o01@1",
  "title": "Exit Saves Position",
  "criteria": [
    "The ordered transcript opens MediaLibrary-grid-video-viewing-storage-16m01s.mp4 from a baseline whose viewingState has zero viewing, resumable, completed, and invalid records; playback then reaches at least 20 seconds with at least 300 seconds remaining before the pre-exit viewing-storage snapshot and the real PlayerUI-InfoBar-button-back action.",
    "The pre-exit snapshot has one activePlayback with viewingStateAuthority enchron-persistence, lifecycle playing, endedNaturally false, a non-none sessionID, canonical mediaIdentity and contentRevision, positionSeconds at least 20, and durationSeconds minus positionSeconds at least 300.",
    "The final snapshot has no activePlayback and exactly one resumable, non-completed viewing entry whose mediaIdentity and contentRevision equal the pre-exit activePlayback, whose authority is enchron-persistence, and whose positionSeconds differs from the pre-exit positionSeconds by no more than 5 seconds; invalidRecordCount remains zero.",
    "The baseline, pre-exit, and final snapshots have one unchanged viewingState.storeIdentity, and the pre-exit and final viewingStorageObservation records bind respectively the baseline digest and both earlier digests through priorSnapshotDigests."
  ],
  "negativeControls": [
    "A wait-position receipt or Back action without all three bound viewingStorageObservation snapshots is inadmissible; an unavailable required field or unresolved result binding is Indeterminate.",
    "A short or near-end playback, changed media identity or content revision, completed rather than resumable state, more than five seconds of persistence drift, a remaining activePlayback, a changed store identity, or any invalid record violates the contract."
  ]
}
---
# Exit Saves Position

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
