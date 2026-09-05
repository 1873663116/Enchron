---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.completed-media-starts-from-beginning.o01@1",
  "title": "Completed Media Starts From Beginning",
  "criteria": [
    "The ordered transcript opens MediaLibrary-grid-video-viewing-storage-16m01s-b.mp4 from an empty viewing-state baseline, reaches playing, requests playback.seek positionMillionths 997000, and observes lifecycle ended before any Back action.",
    "relatedResults inline the ended viewingStorageObservation from call 09: activePlayback.endedNaturally is true for a canonical mediaIdentity and contentRevision. After Back, the inlined persisted snapshot from call 11 has exactly one completed entry for that identity and revision with completed true, status completed, and positionSeconds equal to durationSeconds, with no resumable entry and no invalid record.",
    "relatedResults inline the PlayerUI-resumeDecision-primary matchedElement from call 13, which is null because no Resume Playback? alert is shown, and the ordered transcript contains no activation of either resume-decision action. Playback reaches playing automatically.",
    "The producer snapshot's activePlayback has a non-none sessionID different from the naturally ended session, the same mediaIdentity and contentRevision, viewingStateAuthority enchron-persistence, endedNaturally false, and positionSeconds from 0 through 5 inclusive under the observed-position bound decided by HC-021. The store still has no resumable entry. relatedResults also inline the empty baseline snapshot from call 01."
  ],
  "negativeControls": [
    "A near-end seek or Back without an inlined natural Ended snapshot and endedNaturally true cannot establish completion; a missing structured end, persistence, or resume-alert observation is Indeterminate.",
    "A resume alert, resume-decision activation, resumable marker, reused session, changed identity or revision, or reopened position above five seconds violates the start-over contract.",
    "priorSnapshotDigests hashes without the inlined ended and persisted viewingStorageObservation objects cannot establish completed entry contents or matchedElement null."
  ]
}
---
# Completed Media Starts From Beginning

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
