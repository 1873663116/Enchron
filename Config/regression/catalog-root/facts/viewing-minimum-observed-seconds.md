---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:viewing.minimum-observed-seconds",
  "title": "Viewing minimum observed seconds",
  "statement": "A shorter local viewing interval leaves existing state unchanged.",
  "valueType": "integer",
  "value": 15,
  "provenance": {
    "kind": "product-constant",
    "path": "Modules/Playback/Domain/ViewingState.swift",
    "pattern": "minimumActualPlaybackSeconds:\\s*Double\\s*=\\s*(.+)$",
    "transform": "integer"
  }
}
---
# Viewing minimum observed seconds

The blueprint recorded design-time status `reviewed` and value `15`.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
