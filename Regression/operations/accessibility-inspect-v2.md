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
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [],
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
    "digest": "sha256:be8f6611010ac088ec845d293391ef8c8461bafd044d341caca45c9799e6a728"
  }
}
---
# Accessibility Inspect

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
