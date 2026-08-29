---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:input.device-hub-window-pinch-proves-delivery",
  "title": "Input device hub window pinch proves delivery",
  "statement": "A simulator Device Hub gaze-and-pinch plus the application probe proves the window input pipeline.",
  "valueType": "boolean",
  "value": true,
  "provenance": {
    "kind": "decision",
    "decision": "HC-005"
  }
}
---
# Input device hub window pinch proves delivery

The blueprint recorded design-time status `proposal` and value `true`.

Approved design decision `HC-005` is recorded in `Regression/semantic-authority.json`; it excludes subjective input feel and does not interrupt a run.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
