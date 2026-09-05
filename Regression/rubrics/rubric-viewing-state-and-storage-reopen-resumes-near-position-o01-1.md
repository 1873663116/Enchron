---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.reopen-resumes-near-position.o01@1",
  "title": "Reopen Resumes Near Position",
  "criteria": [
    "The ordered transcript establishes an empty viewing-state baseline, plays MediaLibrary-grid-video-viewing-storage-16m01s.mp4 beyond 20 seconds with at least 300 seconds remaining, captures its active identity and session, and exits through PlayerUI-InfoBar-button-back. relatedResults inline the persisted viewingStorageObservation from call 10 with exactly one resumable entry for that mediaIdentity and contentRevision.",
    "relatedResults inline the PlayerUI-resumeDecision-primary matchedElement from call 12, which is present because the Resume Playback? alert is shown, and the PlayerUI-resumeDecision-primary activation response from call 13, which succeeded. Playback then reaches lifecycle playing without a reset, clear, different media open, or content mutation between persistence and reopen.",
    "The producer activePlayback has a non-none sessionID different from the inlined pre-exit sessionID in call 08's viewingStorageObservation, viewingStateAuthority enchron-persistence, the same mediaIdentity and contentRevision as the inlined persisted entry, and positionSeconds greater than zero and within the five-second observed-position bound of that persisted entry decided by HC-021.",
    "relatedResults also inline the empty baseline from call 01. Every compared viewing entry has authority enchron-persistence and invalidRecordCount is zero."
  ],
  "negativeControls": [
    "A visible alert without a successful primary action, or a primary action without the inlined matched primary button and final structured snapshot, is inadmissible.",
    "Reusing the old session, starting at zero, differing by more than five seconds, selecting a stale identity or revision, using another viewing authority, or retaining invalid records violates the resume contract.",
    "priorSnapshotDigests hashes without the inlined persisted viewingStorageObservation and resume-primary matchedElement cannot establish the five-second bound or alert presence."
  ]
}
---
# Reopen Resumes Near Position

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
