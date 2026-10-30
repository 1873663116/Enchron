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
    "digest": "sha256:62531e988a9e70e62e672faaf49818793b6fff7936a62ac2a4fbdaf657e4a527"
  }
}
---
# App Relaunch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
