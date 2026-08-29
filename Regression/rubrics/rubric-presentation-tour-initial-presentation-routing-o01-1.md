---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.initial-presentation-routing.o01@1",
  "title": "Initial Presentation Routing",
  "criteria": [
    "With no override, sdr-bframe-multiaudio-avsync-120s.mp4 resolves to Flat/window with source provenance, while registered internal-apple-apmp-180-v1 resolves from its real APMP signalling to equirectangular180/portal with source provenance.",
    "Within separate attempts, persisting Flat for the APMP media identity makes its next open settle in window, and persisting equirectangular180 for the flat 120-second media identity makes its next open settle in portal; each reopen preserves identity/content revision and reports user provenance."
  ],
  "negativeControls": [
    "Using 360.mp4 as if it carried reviewed embedded signalling, sharing override state between cases, using a different identity/revision on reopen, or accepting an unspecified route cannot satisfy the rubric."
  ]
}
---
# Initial Presentation Routing

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
