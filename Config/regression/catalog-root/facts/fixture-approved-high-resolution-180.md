---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:fixture.approved-high-resolution-180",
  "title": "Fixture approved high resolution 180",
  "statement": "An approved non-sensitive high-resolution 180-degree visual reference has not been selected.",
  "valueType": "string",
  "value": "unselected",
  "provenance": {
    "kind": "decision",
    "decision": "HC-006"
  }
}
---
# Fixture approved high resolution 180

The blueprint recorded design-time status `unresolved` and value `"unselected"`.

Approved design decision `HC-006` is recorded in `Regression/semantic-authority.json`. Its required fixture work is a compile-time input condition and does not interrupt a run.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
