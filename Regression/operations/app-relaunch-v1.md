---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:app.relaunch@1",
  "title": "App Relaunch",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "app.session",
    "issue.surface",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "ui.navigation",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:d71725e8567bc710b16a8c0ac9304c09571bc4df01df1a1799500c4d49dd04a5"
  }
}
---
# App Relaunch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
