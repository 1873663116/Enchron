---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.window-to-portal-format-route.o01@1",
  "title": "Window To Portal Format Route",
  "criteria": [
    "Applying a panoramic format from window reaches presentation=portal, attached=portal, transition=none, and pendingSpatialEffect=none.",
    "The portal requests the reviewed 1280x720 default and uses a freely resizable window policy after the format revision updates."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Entering panorama directly, leaving a pending effect, or retaining the locked flat-window geometry violates the rubric."
  ]
}
---
# Window To Portal Format Route

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
