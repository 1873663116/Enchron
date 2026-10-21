---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.window-docked-round-trip.o01@1",
  "title": "Window Docked Round Trip",
  "criteria": [
    "spatialState.fields reports attached=docked, rendererConsumer, and playbackEntity from PlayerUI-spatial-state, and summon/action record toggleControls then PlayerPanel-button-exit-spatial.",
    "fields after exit report presentation=window, attached=window, the same session as spatialState.fields.session, windowGeometryPolicyKind=aspectLocked, and windowGeometryResizingRestriction=uniform."
  ],
  "negativeControls": [
    "Controller success without the application-side delivery event is not evidence of product behavior.",
    "Missing sequence numbers, mismatched revisions, reversed order, or a truncated timing window cannot satisfy the rubric.",
    "Omitting spatialState, attached other than docked, a new media session, missing environment selection, incomplete dock settlement, or return to portal violates the rubric."
  ]
}
---
# Window Docked Round Trip

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
