---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.panorama-to-portal-exit.o01@1",
  "title": "Panorama To Portal Exit",
  "criteria": [
    "The spatial controls expose Return to Portal and application-side delivery starts the panorama-to-portal transition.",
    "The final snapshot reports presentation=portal, attached=portal, transition=none, and no pending spatial effect while preserving playback position."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Exiting to window, losing playback position, or leaving immersive attachment ownership active violates the rubric."
  ]
}
---
# Panorama To Portal Exit

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
