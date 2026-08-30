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
    "digest": "sha256:62e8b68e2824de74f8b2e2bf5c30dcffb0d4faf88ffe8cba81d325e202e6ed7c"
  }
}
---
# App Relaunch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
