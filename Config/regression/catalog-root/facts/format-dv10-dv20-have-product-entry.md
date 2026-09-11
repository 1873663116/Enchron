---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:format.dv10-dv20-have-product-entry",
  "title": "Format dv10 dv20 have product entry",
  "statement": "Current DASH and HLS manifest fixtures have no product discovery route. The feature commitment named profiles 10 and 20 until 2026-09-11 and now names profile 10; decision HC-007, which this Fact rests on, still names both.",
  "valueType": "boolean",
  "value": false,
  "provenance": {
    "kind": "decision",
    "decision": "HC-007"
  }
}
---
# Format dv10 dv20 have product entry

The blueprint recorded design-time status `unresolved` and value `false`.

Approved design decision `HC-007` is recorded in `Regression/semantic-authority.json`. Its required fixture work is a compile-time input condition and does not interrupt a run.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
