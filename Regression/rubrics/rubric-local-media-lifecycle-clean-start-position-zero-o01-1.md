---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.clean-start-position-zero.o01@1",
  "title": "Clean Start Position Zero",
  "criteria": [
    "After the ordered reset, registered import, and open calls succeed, the first stable playback snapshot reports the expected media identity, lifecycle=Playing, a zero-start position, and no resume decision."
  ],
  "negativeControls": [
    "A non-zero persisted position, resume decision, wrong media identity, or lifecycle other than Playing violates the clean-start contract."
  ]
}
---
# Clean Start Position Zero

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
