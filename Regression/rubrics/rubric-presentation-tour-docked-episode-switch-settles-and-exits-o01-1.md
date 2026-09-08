---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.docked-episode-switch-settles-and-exits.o01@1",
  "title": "Docked Episode Switch Settles Again",
  "criteria": [
    "The bound PlayerUI-spatial-state accessibility tree, read with context docked, requireMatchedElement true, summonControls true and deadlineSeconds 30 right after selecting 180_3D.mp4 from PlayerPanel-menu-more → PlayerPanel-menu-episodes (labelsAfterIdentifiers true), reports spatialState.fields.attached=docked with a rendererConsumer and playbackEntity present, proving the shell re-settled rather than staying pinned to the pre-switch surface.",
    "spatialState.fields.mediaName (or the equivalent media identity field carried by PlayerUI-spatial-state) names 180_3D.mp4, not sdr-bframe-multiaudio-avsync-120s.mp4, so the observation is bound to the entity produced by the in-place switch and cannot be satisfied by a stale pre-switch snapshot."
  ],
  "negativeControls": [
    "A missing PlayerUI-spatial-state matchedElement, requireMatchedElement false, or a read taken before the episode-menu activation is Indeterminate, not Satisfied.",
    "attached other than docked, an absent rendererConsumer/playbackEntity, or a mediaName still naming the original file (evidence of the reported in-place relaunch onto the released screen entity) fails the bound case."
  ]
}
---
# Docked Episode Switch Settles Again

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
