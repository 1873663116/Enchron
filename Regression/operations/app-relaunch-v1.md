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
    "digest": "sha256:ed10e583b4e69fa6fdad2cf7047126cf19166f9c7971ae55eb03cc7ac975ea6e"
  }
}
---
# App Relaunch

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
