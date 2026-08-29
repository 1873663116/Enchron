---
{
  "schema": "enchron.regression.fact",
  "schemaVersion": 1,
  "id": "fact:viewing.minimum-media-duration-seconds",
  "title": "Viewing minimum media duration seconds",
  "statement": "Local media shorter than this threshold does not retain viewing progress.",
  "valueType": "integer",
  "value": 900,
  "provenance": {
    "kind": "product-constant",
    "path": "Modules/Playback/Domain/ViewingState.swift",
    "pattern": "minimumContentDurationSeconds:\\s*Double\\s*=\\s*(.+)$",
    "transform": "integer"
  }
}
---
# Viewing minimum media duration seconds

The blueprint recorded design-time status `reviewed` and value `900`.

The declaration does not certify a value for a run. A compile request must supply the reviewed value and its review provenance.
