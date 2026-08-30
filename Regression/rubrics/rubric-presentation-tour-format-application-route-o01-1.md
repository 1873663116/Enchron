---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.format-application-route.o01@1",
  "title": "Format Application Route",
  "criteria": [
    "The panoramic-to-portal case uses 180_3D.mp4 and the flat-to-window case uses sdr-bframe-multiaudio-avsync-120s.mp4, so neither case inherits the other case's media-scoped override.",
    "Each trace records arm→format apply→terminal settlement→fetch→disarm; equirectangular180 settles in portal with user projection/packing/revision, while Flat settles in window with flat/mono user state."
  ],
  "negativeControls": [
    "Reusing one media identity across both cases, disarming before the generation-bound trace fetch, direct automatic panorama entry, stale revision, mismatched packing, or Flat remaining in portal fails the rubric."
  ]
}
---
# Format Application Route

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
