---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.artwork-captured-on-exit.o01@1",
  "title": "Artwork Captured On Exit",
  "criteria": [
    "The bound capture inlines three frame manifests and the earlier artwork readings of one attempt, and an exact digest chain decides the claim, which is the comparison HC-021 asks for before any measured bound. The pre-exit reading relatedResults carries from the first capture has a real SHA-256 artworkCurrentDigest for the frame the session was displaying and an artworkStoredDigest of none, because the attempt opened by clearing the artwork cache. The reading taken after the first exit, on the same artworkKey, has a real SHA-256 artworkStoredDigest and artworkStoredBytes above zero: the exit wrote artwork where there was none. That exit is PlayerUI-InfoBar-button-back, which reaches saveCurrentArtwork through stopPlayback and cancelPlaybackLaunchAndPersistProgress (Modules/Playback/PlaybackLaunchCoordinator.swift:551-589). Its four frames are taken on the browser after the exit, so the fixture's card carries that artwork; set against the pre-exit playback frames of the first manifest it shows the same scene rather than placeholder art, a solid fill, or a different moment of the clip. No numeric crop or colour-distance tolerance is applied and none may be invented: HC-021 still lists measure-artwork-bound as required work, and the digest chain above is the exact comparison it says to prefer.",
    "A second exit at a different position replaces the first artwork. The attempt reopens the fixture and waits past a position later than the one the first exit left, and the reading taken there on the same artworkKey still reports the first exit's artworkStoredDigest — nothing but an exit rewrites the store — while its artworkCurrentDigest differs from the first capture's, so the frame about to be stored is a different one. The bound capture, taken after that second exit through the same key, reports an artworkStoredDigest that differs from the first exit's with artworkStoredBytes above zero. Every reading names the same artworkKey, so one media identity is in play throughout."
  ],
  "negativeControls": [
    "A 1x1, corrupt, single-frame, or provenance-free capture is Indeterminate and never Satisfied, as is an artworkStoredDigest of none in a reading taken after an exit.",
    "Pure black, a solid-colour card, repeated identical frames inside a pre-exit playback capture, or a post-exit card showing a different scene from that capture's frames is a negative control that forces Violated once capture validity is established.",
    "A stale prior frame, placeholder art, missing card art, a second exit that leaves the first exit's artworkStoredDigest in place, or an artworkKey that changes between readings violates the rubric."
  ]
}
---
# Artwork Captured On Exit

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
