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
    "digest": "sha256:d71725e8567bc710b16a8c0ac9304c09571bc4df01df1a1799500c4d49dd04a5"
  }
}
---
# Media Open

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
