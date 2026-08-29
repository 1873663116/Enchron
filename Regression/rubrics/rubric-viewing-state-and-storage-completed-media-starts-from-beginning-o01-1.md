---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:viewing-state-and-storage.completed-media-starts-from-beginning.o01@1",
  "title": "Completed Media Starts From Beginning",
  "criteria": [
    "From an empty viewing-state baseline, the transcript opens MediaLibrary-grid-video-viewing-storage-16m01s-b.mp4, reaches playing, requests playback.seek positionMillionths 997000, and then observes lifecycle ended before any Back action.",
    "The ended snapshot has activePlayback.endedNaturally true for a canonical mediaIdentity and contentRevision; after Back, the persisted snapshot has exactly one completed entry for that identity and revision with completed true, status completed, and positionSeconds equal to durationSeconds, with no resumable entry and no invalid record.",
    "The second open contains no activation of either resume-decision action, its PlayerUI-resumeDecision-panel inspection has matchedElement null, and playback reaches playing automatically.",
    "The final activePlayback has a non-none sessionID different from the naturally ended session, the same mediaIdentity and contentRevision, viewingStateAuthority enchron-persistence, endedNaturally false, and positionSeconds from 0 through 5 inclusive; the final store still has no resumable entry and binds the baseline, ended, and persisted snapshot digests."
  ],
  "negativeControls": [
    "A near-end seek or Back without an observed natural Ended state and endedNaturally true cannot establish completion; missing structured end or persistence evidence is Indeterminate.",
    "A resume panel, resume-decision activation, resumable marker, reused session, changed identity or revision, or reopened position above five seconds violates the start-over contract."
  ]
}
---
# Completed Media Starts From Beginning

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
