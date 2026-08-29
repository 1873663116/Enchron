---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.portal-to-panorama-explicit-entry.o01@1",
  "title": "Portal To Panorama Explicit Entry",
  "criteria": [
    "The Portal hierarchy exposes the Enter Panorama action with the declared accessibility label after portal steady state.",
    "Application-side delivery is followed by the matching presentation request, attachment ownership transfer, and panorama settlement for the same revision."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Automatic entry without the explicit action, controller-only success, or settlement for another revision violates the rubric."
  ]
}
---
# Portal To Panorama Explicit Entry

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
