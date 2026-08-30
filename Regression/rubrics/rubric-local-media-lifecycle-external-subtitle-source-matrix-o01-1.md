---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1",
  "title": "External Subtitle Source Matrix",
  "criteria": [
    "For the bound caseKey, the independent attempt opens its real media identity and the producer frames carry relatedResults inlined from that same attempt's playback.select-subtitle@1 call: host is playerUI, sourceKind is the case's registered kind (local-sidecar for local-sidecar, source-directory-sidecar for webdav-sidecar, emby-external-stream for emby-external-stream), and deadlineSeconds is within 1 through 90. The local-sidecar and webdav-sidecar attempts additionally bind trackLabel to the registered sdr-bframe-aggregate-30s.zh-CN.srt sidecar (Tests/Fixtures/fixture-registry.json:472), which is what separates it from the sdr-bframe-aggregate-30s.styled.ass sidecar registered beside it at line 482 and staged into the same directory. The Emby case binds no label because regression_emby_source.py:33 seeds exactly one external file; it starts playback from the series-page episode card labeled Enchron Regression Episode and discovers that sole external track from the verified seed receipt.",
    "The inlined discoveredTracks hold only identifiers under external.subtitle., selectedTrack names exactly one of them carrying the case's sourceKind and, for local-sidecar and webdav-sidecar, label sdr-bframe-aggregate-30s.zh-CN.srt; settlement.outcome is selected with terminalTrackID equal to that selectedTrack.id; and identityObservation reports sessionPreserved, mediaPreserved, sourceIdentityPreserved and contentRevisionPreserved all true beside the unchanged session, mediaName, sourceIdentity and contentRevision it preserved. The following three-frame producer then shows the reviewed external cue rather than an embedded subtitle."
  ],
  "negativeControls": [
    "A mismatched source case, Catalog-authored dynamic track ID, direct state injection, missing authenticated source, ambiguous discovery result, identity or revision change, missing external cue, embedded cue, fewer than three changing frames, or source-kind mismatch fails the bound case."
  ]
}
---
# External Subtitle Source Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
