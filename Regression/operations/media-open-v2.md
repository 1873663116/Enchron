---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:media.open@2",
  "title": "Media Open",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "identifier",
        "type": "string",
        "required": true
      },
      {
        "name": "expectedLanding",
        "type": "string",
        "required": true
      },
      {
        "name": "expectedIssueCategory",
        "type": "string",
        "required": false
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "issue.surface",
    "playback.position",
    "playback.selection",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:a2f53ab9b72521f76526433bf7a40437a4f693b546cab25a6e01331efa6349ef"
  }
}
---
# Media Open

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
