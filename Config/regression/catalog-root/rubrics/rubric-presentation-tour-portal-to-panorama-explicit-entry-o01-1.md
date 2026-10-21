---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.portal-to-panorama-explicit-entry.o01@1",
  "title": "Portal To Panorama Explicit Entry",
  "criteria": [
    "The bound producer's preActionMatchedElement is the observation the entry route recorded for the element it was about to tap in portal steady state: identifier PlayerUI-TopAction-resumePanorama, accessibility label Enter Panorama, isEnabled and isHittable true. A null preActionMatchedElement, another identifier, or an empty label is Indeterminate; the summon response's hierarchy text is not a substitute, because portal chrome lives outside the printed main-window tree.",
    "Application-side delivery is followed by the matching presentation request, attachment ownership transfer, and panorama settlement for the same revision."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Automatic entry without the explicit action, controller-only success, or settlement for another revision violates the rubric.",
    "A preActionMatchedElement copied from the summon tap, from a later snapshot, or from any element other than the one the route tapped cannot establish criterion 1."
  ]
}
---
# Portal To Panorama Explicit Entry

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
