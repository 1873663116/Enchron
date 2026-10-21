---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.window-to-portal-format-route.o01@1",
  "title": "Window To Portal Format Route",
  "criteria": [
    "Applying a panoramic format from window reaches presentation=portal, attached=portal, transition=none, and pendingSpatialEffect=none.",
    "The bound fetch terminalState reports windowGeometryPolicyKind=aspectLocked, windowGeometryRequestedIdealWidth=1280, windowGeometryRequestedIdealHeight=720, and windowGeometryResizingRestriction=uniform from WindowPlaybackGeometryPolicy.portal (WindowPlaybackRootView.swift:166-199)."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Entering panorama directly, leaving a pending effect, retaining locked flat-window geometry, or claiming a freely resizable PolicyKind the diagnostic vocabulary cannot emit violates the rubric."
  ]
}
---
# Window To Portal Format Route

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
