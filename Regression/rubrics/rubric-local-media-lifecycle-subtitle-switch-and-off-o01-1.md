---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1",
  "title": "Subtitle Switch And Off",
  "criteria": [
    "Selecting the embedded text and bitmap cases changes the selected track and displays the case-specific reference overlay.",
    "Selecting Off removes subtitle pixels and marks only Off selected; selecting the prior track restores its reference overlay."
  ],
  "negativeControls": [
    "A 1x1, corrupt, single-frame, or provenance-free capture is Indeterminate and never Satisfied.",
    "Pure black, solid color, repeated identical frames, or a reference mismatch is a negative control that forces Violated when capture validity is established.",
    "Treating Off as an empty track, retaining subtitle pixels after Off, or showing the wrong case reference violates the rubric."
  ]
}
---
# Subtitle Switch And Off

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
