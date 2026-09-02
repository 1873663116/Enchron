---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:harness.reset-product-state@2",
  "title": "Harness Reset Product State",
  "role": "setup",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "rootFolderName",
        "type": "string",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "app.session",
    "cache.state",
    "certificate.trust",
    "issue.surface",
    "library.contents",
    "media.format",
    "playback.position",
    "playback.selection",
    "playback.session",
    "presentation.mode",
    "presentation.state",
    "renderer.graph",
    "settings.state",
    "source.connection",
    "source.session",
    "ui.navigation",
    "ui.state",
    "viewing.progress",
    "viewing.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:06733d4f3fc59b242183989211ccf4287b078265d302639a7c93077ae6df81ac"
  }
}
---
# Harness Reset Product State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
