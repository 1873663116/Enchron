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
    "digest": "sha256:3b3773d1e84f8ddecd3a3a7839b29f3a4f4f4f949d65840d0efcf25c793ac62d"
  }
}
---
# Diagnostics Browse Hierarchy

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
