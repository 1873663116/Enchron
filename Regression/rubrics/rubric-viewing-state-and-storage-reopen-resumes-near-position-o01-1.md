---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.reopen-resumes-near-position.o01@1",
  "title": "Reopen Resumes Near Position",
  "criteria": [
    "The transcript establishes an empty viewing-state baseline, plays MediaLibrary-grid-video-viewing-storage-16m01s.mp4 beyond 20 seconds with at least 300 seconds remaining, captures its active identity and session, exits through PlayerUI-InfoBar-button-back, and then captures exactly one persisted resumable entry for that mediaIdentity and contentRevision.",
    "The second open matches PlayerUI-resumeDecision-panel in the window hierarchy, activates PlayerUI-resumeDecision-primary, and reaches lifecycle playing without a reset, clear, different media open, or content mutation between persistence and reopen.",
    "The final activePlayback has a non-none sessionID different from the pre-exit sessionID, viewingStateAuthority enchron-persistence, the same mediaIdentity and contentRevision as the persisted entry, and positionSeconds greater than zero and within the five-second observed-position bound of the persisted entry positionSeconds decided by HC-021.",
    "The final viewingStorageObservation binds the baseline, pre-exit, and persisted snapshot digests in order; every compared viewing entry has authority enchron-persistence and invalidRecordCount is zero."
  ],
  "negativeControls": [
    "A visible panel without a successful primary action, or a primary action without the exact matched panel and final structured snapshot, is inadmissible.",
    "Reusing the old session, starting at zero, differing by more than five seconds, selecting a stale identity or revision, using another viewing authority, or retaining invalid records violates the resume contract."
  ]
}
---
# Reopen Resumes Near Position

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
