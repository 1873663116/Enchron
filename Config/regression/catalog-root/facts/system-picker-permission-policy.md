---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:system-picker.permission-policy",
  "title": "System picker permission policy",
  "statement": "Unattended runs either start from reviewed permission state or report an infrastructure block; no human answers the scene.",
  "valueType": "string",
  "value": "preauthorize-or-block",
  "provenance": {
    "kind": "decision",
    "decision": "HC-001"
  }
}
---
# System picker permission policy

The blueprint recorded design-time status `proposal` and value `"preauthorize-or-block"`.

Approved design decision `HC-001` is recorded in `Regression/semantic-authority.json`; permission state is established before a run and does not introduce a human checkpoint.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
