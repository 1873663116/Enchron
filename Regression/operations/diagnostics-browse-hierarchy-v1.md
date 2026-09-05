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
    "digest": "sha256:3c1fe7eecc5a1d752b086e109d55959e59ee7db0be3b2564d535351fb8101919"
  }
}
---
# Diagnostics Browse Hierarchy

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
