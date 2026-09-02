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
    "digest": "sha256:d71725e8567bc710b16a8c0ac9304c09571bc4df01df1a1799500c4d49dd04a5"
  }
}
---
# Diagnostics Browse Hierarchy

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
