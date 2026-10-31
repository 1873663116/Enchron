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
    "digest": "sha256:37845e83cbb27174a8d5761b0e23127bc395031896d2772b640a04b5909f2e52"
  }
}
---
# Diagnostics Browse Hierarchy

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
