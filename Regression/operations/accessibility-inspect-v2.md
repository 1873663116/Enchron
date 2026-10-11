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
        "name": "mediaServerProvider",
        "type": "string",
        "required": false
      },
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
    "digest": "sha256:e4cc3f40583b97779d45cecb4c85a9a1c84b36e916446013ac41753d4508359e"
  }
}
---
# Accessibility Inspect

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
