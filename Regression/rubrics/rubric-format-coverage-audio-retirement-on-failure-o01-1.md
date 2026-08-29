---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.audio-retirement-on-failure.o01@1",
  "title": "Audio Retirement On Failure",
  "criteria": [
    "The structural-test artifact exits zero and names the exact allowlisted PlaybackCore test for this failure phase.",
    "That phase-specific test proves audio retirement is nonfatal and proves a subsequent seek in the same media session advances video beyond the target."
  ],
  "negativeControls": [
    "A passing test for another failure phase cannot satisfy this case.",
    "A compile-only result, a zero-test selection, or a structural artifact whose command differs from the allowlisted command cannot satisfy the rubric.",
    "Any fatal lifecycle transition, stalled post-seek video, or replacement media session violates the commitment."
  ]
}
---
# Audio Retirement On Failure

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
