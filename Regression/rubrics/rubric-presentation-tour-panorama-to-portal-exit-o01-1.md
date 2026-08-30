---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.panorama-to-portal-exit.o01@1",
  "title": "Panorama To Portal Exit",
  "criteria": [
    "The spatial controls expose PlayerPanel-button-exit-spatial after toggleControls, and application-side delivery starts the panorama-to-portal transition.",
    "The final snapshot reports presentation=portal, attached=portal, transition=none, and pendingSpatialEffect=none, and abs(fields.position - preExitSpatialState.fields.position) is at most 5 seconds under the observed-position bound decided by HC-021 after exact pre-exit target binding from PlayerUI-spatial-state."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Exiting to window, omitting preExitSpatialState, losing playback position by more than 5 seconds, or leaving immersive attachment ownership active violates the rubric."
  ]
}
---
# Panorama To Portal Exit

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
