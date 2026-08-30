---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.signalled-media-classification.o01@1",
  "title": "Signalled Media Classification",
  "criteria": [
    "The source classification, effective presentation, attachment, projection, and packing agree with the reviewed fixture declaration for the case.",
    "Three valid frames show non-solid content after the declared presentation settles, and time-separated frame pairs have FFmpeg SSIM no greater than 0.995, the VISUAL_FROZEN_SSIM threshold in Scripts/verification/playback_mode_matrix.py:1329."
  ],
  "negativeControls": [
    "If any required modality is invalid or missing, the result is Indeterminate rather than inferred from the remaining modality.",
    "Contradictory valid artifacts produce Indeterminate; no majority vote or best-effort selection is permitted.",
    "Landing in a presentation that contradicts source signalling or treating a 4-second fixture timeout as success violates the rubric."
  ]
}
---
# Signalled Media Classification

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
