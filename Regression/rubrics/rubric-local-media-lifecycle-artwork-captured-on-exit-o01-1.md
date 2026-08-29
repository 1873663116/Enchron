---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.artwork-captured-on-exit.o01@1",
  "title": "Artwork Captured On Exit",
  "criteria": [
    "The pre-exit playback frame and the post-exit card artwork match within the reviewed crop and color-distance tolerances.",
    "A second exit at a different position replaces the first artwork without any additional media read in the server or byte-source trace."
  ],
  "negativeControls": [
    "A 1x1, corrupt, single-frame, or provenance-free capture is Indeterminate and never Satisfied.",
    "Pure black, solid color, repeated identical frames, or a reference mismatch is a negative control that forces Violated when capture validity is established.",
    "A stale prior frame, placeholder art, missing card art, or extra media read violates the rubric."
  ]
}
---
# Artwork Captured On Exit

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
