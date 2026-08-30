---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1",
  "title": "Dolby Vision Cross Compatibility Switch",
  "criteria": [
    "The bound artifact contains exactly one three-frame Playing sequence at 1000 ms minimum intervals with stable session and revision, increasing position, distinct content attachments, non-none pixel formats, and no issue.",
    "The bound capture matches the registered case: profile-8-hdr10={relatedResults[0] tappedIdentifiers PlayerUI-window-playback-surface→PlayerUI-TopAction-videoFormat→PlayerUI-VideoFormat-HDRFallback→PlayerUI-VideoFormat-apply, includeHDRFallback true, dolbyVisionProfile=8, dolbyVisionCrossCompatibilityID=1, dolbyVisionHasEnhancementLayer=false, rendererTransferFunction in the closed 2084/PQ set, source format atoms preserved}; profile-8-hlg={the same transaction and includeHDRFallback, dolbyVisionProfile=8, dolbyVisionCrossCompatibilityID=4, dolbyVisionHasEnhancementLayer=false, rendererTransferFunction in the closed HLG/B67 set, source format atoms preserved}; profile-5-no-fallback={relatedResults[0] assertAbsentObservations after PlayerUI-TopAction-videoFormat with PlayerUI-VideoFormat-HDRFallback exists=false, no fallback mutation after cancel, dolbyVisionProfile=5, dolbyVisionCrossCompatibilityID=0, dolbyVisionHasEnhancementLayer=false, source and renderer Dolby Vision atom facts retained}."
  ],
  "negativeControls": [
    "A relatedResults path, source tuple, renderer transfer, or format-atom row that differs from the bound case, HDRFallback offered for Profile 5 (assertAbsentObservations after videoFormat with exists or isHittable true), fewer than three valid frames, repeated attachments, or non-advancing playback fails the bound case."
  ]
}
---
# Dolby Vision Cross Compatibility Switch

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
