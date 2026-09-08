---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:accessibility.inspect@2",
  "title": "Accessibility Inspect",
  "role": "evidence",
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
        "name": "identifier",
        "type": "string",
        "required": true
      },
      {
        "name": "index",
        "type": "integer",
        "required": false
      },
      {
        "name": "requireMatchedElement",
        "type": "boolean",
        "required": false
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": false
      },
      {
        "name": "summonControls",
        "type": "boolean",
        "required": false
      },
      {
        "name": "relatedResults",
        "type": "string-list",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "accessibility.tree",
      "evidenceSchema": "accessibility-tree@1"
    },
    {
      "evidenceType": "emby.evidence",
      "evidenceSchema": "emby-evidence@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:8fe746de8de0d96e7ab0c9fbd04c7ed2e429cb80095c529115b87c0b832eea7c"
  }
}
---
# Accessibility Inspect

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
