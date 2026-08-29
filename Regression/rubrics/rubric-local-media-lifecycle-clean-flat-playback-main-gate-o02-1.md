---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.clean-flat-playback-main-gate.o02@1",
  "title": "Clean Flat Playback Main Gate",
  "criteria": [
    "At least three 1920x1080-or-valid-host frames contain real non-solid content.",
    "Time-separated frames differ beyond the reviewed freeze threshold while retaining the same fixture identity."
  ],
  "negativeControls": [
    "A 1x1, corrupt, single-frame, or provenance-free capture is Indeterminate and never Satisfied.",
    "Pure black, solid color, repeated identical frames, or a reference mismatch is a negative control that forces Violated when capture validity is established.",
    "Black output, a solid frame, repeated identical frames, or capture from another session violates the visual gate."
  ]
}
---
# Clean Flat Playback Main Gate

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
