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
    "digest": "sha256:37845e83cbb27174a8d5761b0e23127bc395031896d2772b640a04b5909f2e52"
  }
}
---
# App Relaunch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
