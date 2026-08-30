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
    "digest": "sha256:be8f6611010ac088ec845d293391ef8c8461bafd044d341caca45c9799e6a728"
  }
}
---
# Media Open

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
