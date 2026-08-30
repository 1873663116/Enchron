---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1",
  "title": "Subtitle Switch And Off",
  "criteria": [
    "Selecting ffmpeg.subtitle.3 displays the generated SubRip cue containing 'Enchron 字幕验证' and selecting ffmpeg.subtitle.5 displays the generated DVB bitmap cue titled 'Enchron generated bitmap proof' with its top-safe-area color bars.",
    "Selecting Off removes subtitle pixels and marks only Off selected; selecting ffmpeg.subtitle.3 again restores the generated SubRip cue containing 'Enchron 字幕验证'."
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
