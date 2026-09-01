---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:diagnostics.browse-hierarchy@1",
  "title": "Diagnostics Browse Hierarchy",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "context",
        "type": "string",
        "required": true
      },
      {
        "name": "sourceLabel",
        "type": "string",
        "required": true
      },
      {
        "name": "pathComponents",
        "type": "string-list",
        "required": true
      },
      {
        "name": "sourceReceipt",
        "type": "string",
        "required": false
      },
      {
        "name": "hostShareName",
        "type": "string",
        "required": false
      },
      {
        "name": "expectedVideoName",
        "type": "string",
        "required": false
      },
      {
        "name": "hostShares",
        "type": "string",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "source.session",
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "accessibility.tree",
      "evidenceSchema": "accessibility-tree@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:ad0562e4a35b7077290d5fd11c50817cda086fa9f1438cf2d9ca80ca005050a7"
  }
}
---
# Diagnostics Browse Hierarchy

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
