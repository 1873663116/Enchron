---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.external-subtitle-source-matrix.o01@1",
  "title": "External Subtitle Source Matrix",
  "criteria": [
    "For the bound caseKey, the independent attempt opens its real media identity and invokes playback.select-subtitle with host playerPanel, the matching sourceKind, and deadlineSeconds within 1 through 90. Local and WebDAV sidecars use the registered sdr-bframe-aggregate-30s.zh-CN.srt label; the Emby case discovers the sole external track from the verified seed receipt.",
    "The bound Operation discovers only real external.subtitle menu items, selects the unique source-kind and label match, returns the complete selection and identity observations, preserves session, media, source identity, and content revision, and the following three-frame producer shows the reviewed external cue rather than an embedded subtitle."
  ],
  "negativeControls": [
    "A mismatched source case, Catalog-authored dynamic track ID, direct state injection, missing authenticated source, ambiguous discovery result, identity or revision change, missing external cue, embedded cue, fewer than three changing frames, or source-kind mismatch fails the bound case."
  ]
}
---
# External Subtitle Source Matrix

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
