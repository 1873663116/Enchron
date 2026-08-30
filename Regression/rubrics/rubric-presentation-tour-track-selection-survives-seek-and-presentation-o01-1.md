---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1",
  "title": "Track Selection Survives Seek And Presentation",
  "criteria": [
    "The bound attempt opens registered WebDAV sdr-bframe-aggregate-30s.mkv, and relatedResults[1] and relatedResults[3] are two succeeded tapSequence responses, one per menu transaction, each reporting a single command — the controls are summoned through toggleControls before either, so no route step is spent toggling the chrome.",
    "relatedResults[0] and relatedResults[2] are the runner's per-step alsoInspected records for those two transactions. The first carries afterStep values PlayerUI-TopAction-more, then PlayerUI-menu-audio, then PlayerUI-menu-audio-2, in that order. The second carries PlayerUI-TopAction-more, then PlayerUI-menu-subtitles, then label:sdr-bframe-aggregate-30s.zh-CN.srt, in that order, so the sidecar subtitle row was activated inside the same command that opened the menu above it.",
    "The bound post-mutation state preserves the same media identity and the selected audio and subtitle track identities after the mutation registered for its case: seek, docked round trip, portal/window format round trip, or one format replacement. A bound pure spatial transition case also preserves the media session identity."
  ],
  "negativeControls": [
    "The nonexistent Commentary or external-reference identifiers, a same-label/different-ID fallback, selection loss, or session replacement during the docked pure transition fails the rubric.",
    "A split nested-menu route fails the rubric: more than one controller command bound to one menu transaction, an alsoInspected record whose label step precedes its identifier steps, or a record with fewer afterStep values than the route has steps."
  ]
}
---
# Track Selection Survives Seek And Presentation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
