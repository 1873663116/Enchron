---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.subtitle-switch-and-off.o01@1",
  "title": "Subtitle Switch And Off",
  "criteria": [
    "For caseKey embedded-text, the bound frames show the generated SubRip cue containing Enchron 字幕验证 after selecting ffmpeg.subtitle.3.",
    "For caseKey embedded-bitmap, the bound frames show the generated DVB bitmap cue titled Enchron generated bitmap proof with its top-safe-area color bars after selecting ffmpeg.subtitle.5.",
    "For caseKey off, the bound frames contain no subtitle pixels after selecting Off and only Off is selected.",
    "For caseKey restore, the bound frames again show Enchron 字幕验证 after selecting ffmpeg.subtitle.3."
  ],
  "negativeControls": [
    "A mismatched case reference, retained subtitle pixels in the Off case, missing expected cue, fewer than three changing valid frames, or blank, pure-color, or repeated attachments fails the bound case."
  ]
}
---
# Subtitle Switch And Off

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
