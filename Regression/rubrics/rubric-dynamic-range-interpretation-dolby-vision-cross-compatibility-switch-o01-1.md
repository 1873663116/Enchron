---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1",
  "title": "Dolby Vision Cross Compatibility Switch",
  "criteria": [
    "For caseKey profile-8-hdr10, the bound artifact follows one surface to videoFormat to HDRFallback to apply transaction, preserves source tuple (8,1,false) and source format atoms, and shows the HDR10/PQ renderer transfer on the published deliveryAccessibilityFields.",
    "For caseKey profile-8-hlg, the bound artifact follows one surface to videoFormat to HDRFallback to apply transaction, preserves source tuple (8,4,false) and source format atoms, and shows the HLG/B67 renderer transfer on the published deliveryAccessibilityFields.",
    "For caseKey profile-5-no-fallback, the bound artifact preserves source tuple (5,0,false), inlines assertAbsentObservations after PlayerUI-TopAction-videoFormat in which PlayerUI-VideoFormat-HDRFallback exists is false, records no fallback mutation after cancel, and retains source and renderer Dolby Vision atom facts.",
    "The bound artifact contains exactly one three-frame Playing sequence at 1000 ms minimum intervals with stable session and revision, increasing position, distinct content attachments, non-none pixel formats, and no issue."
  ],
  "negativeControls": [
    "A mismatched case, changed source tuple or format atoms, fallback offered for Profile 5 (assertAbsentObservations after videoFormat with exists or isHittable true), fewer than three valid frames, repeated attachments, or non-advancing playback fails the bound case."
  ]
}
---
# Dolby Vision Cross Compatibility Switch

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
