---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.initial-presentation-routing.o01@1",
  "title": "Initial Presentation Routing",
  "criteria": [
    "The bound open settles according to the route registered for its case: source-flat resolves sdr-bframe-multiaudio-avsync-120s.mp4 to Flat/window, source-panorama resolves internal-apple-apmp-180-v1 from its real APMP signalling to equirectangular180/portal, persisted-flat resolves the APMP identity to window after persisting Flat, and persisted-panorama resolves the flat 120-second identity to portal after persisting equirectangular180.",
    "The bound open reports the provenance registered for its case, and a reopen decides preservation against the identity that was persisted rather than asserting it. A source-flat or source-panorama case reads formatProvenance source in the bound open's own fields, because nothing in that attempt applied an override. For persisted-flat and persisted-panorama the bound open reads formatProvenance userOverride, and it inlines the reading its own persist attempt took after format.apply@2 returned and before the relaunch: relatedResults[0] is that call's sourceIdentity and relatedResults[1] is its contentRevision, each a sha256: storage key and neither of them none, and the bound open's own sourceIdentity and contentRevision are equal to them character for character. That equality is the whole claim -- the override survived the relaunch attached to the same media identity and the same content revision it was recorded against, not merely to a file with the same name."
  ],
  "negativeControls": [
    "Using 360.mp4 as if it carried reviewed embedded signalling, sharing override state between cases, or accepting an unspecified route cannot satisfy the rubric.",
    "On a reopen, a bound sourceIdentity or contentRevision that differs from the inlined pre-relaunch reading, either value reading none, an inlined reading taken from an attempt other than the one that applied the override, or formatProvenance source where the case registered userOverride violates the persistence claim."
  ]
}
---
# Initial Presentation Routing

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
