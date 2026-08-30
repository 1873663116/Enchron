---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.format-application-route.o01@1",
  "title": "Format Application Route",
  "criteria": [
    "The bound case uses its registered media identity and begins without a media-scoped override from another case: panoramic-to-portal uses 180_3D.mp4, and flat-to-window uses sdr-bframe-multiaudio-avsync-120s.mp4.",
    "The bound trace records arm→format apply→terminal settlement→fetch→disarm and settles according to its registered route: equirectangular180 reaches portal with user projection/packing/revision, while Flat reaches window with flat/mono user state."
  ],
  "negativeControls": [
    "Reusing one media identity across both cases, disarming before the generation-bound trace fetch, direct automatic panorama entry, stale revision, mismatched packing, or Flat remaining in portal fails the rubric."
  ]
}
---
# Format Application Route

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
