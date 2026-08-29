---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1",
  "title": "External Subtitle Source Matrix",
  "criteria": [
    "After the missing local-directory and Emby preparation capabilities are restored, each independent attempt opens its real media identity and invokes operation:playback.select-subtitle@1 with host=playerPanel, the matching sourceKind, and deadlineSeconds within the closed 1...90 range. The local directory bookmark and WebDAV source-directory cases use the exact registered label sdr-bframe-aggregate-30s.zh-CN.srt. The Emby case uses the sole external track from the verified seed receipt and relies on Operation discovery of its dynamic product identifier rather than a Catalog-authored identifier.",
    "The Operation discovers only real external.subtitle.* menu items, selects the unique source-kind/label match, and returns discoveredTracks, selectedTrack, beforeState, selectionResponse, postActionState, settlement, and unchanged session/media/sourceIdentity/contentRevision; the following three-frame producer shows the reviewed external cue rather than an embedded subtitle."
  ],
  "negativeControls": [
    "A Catalog-authored dynamic track ID, single-file importMedia presented as a directory association, empty media relativePath, catalog-v2-external-subtitle, direct state injection, missing authenticated Emby account, unseeded sidecar, ambiguous discovery result, or identity/revision change is inadmissible.",
    "A missing external cue, embedded cue mistaken for the external source, fewer than three valid changing frames, blank/pure-color/repeated attachments, or source-kind mismatch fails the restored matrix."
  ]
}
---
# External Subtitle Source Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
