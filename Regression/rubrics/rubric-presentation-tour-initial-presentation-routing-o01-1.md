---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.initial-presentation-routing.o01@1",
  "title": "Initial Presentation Routing",
  "criteria": [
    "The bound open settles according to the route registered for its case: source-flat resolves sdr-bframe-multiaudio-avsync-120s.mp4 to Flat/window, source-panorama resolves internal-apple-apmp-180-v1 from its real APMP signalling to equirectangular180/portal, persisted-flat resolves the APMP identity to window after persisting Flat, and persisted-panorama resolves the flat 120-second identity to portal after persisting equirectangular180.",
    "The bound open reports the provenance registered for its case. A source-flat or source-panorama case reports source provenance; a persisted-flat or persisted-panorama reopen preserves identity/content revision and reports user provenance."
  ],
  "negativeControls": [
    "Using 360.mp4 as if it carried reviewed embedded signalling, sharing override state between cases, using a different identity/revision on reopen, or accepting an unspecified route cannot satisfy the rubric."
  ]
}
---
# Initial Presentation Routing

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
