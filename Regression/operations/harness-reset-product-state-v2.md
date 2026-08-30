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
    "digest": "sha256:2aca7cf32430446cf0e8e30832a2fbe3fc9653e8f05004679721c834e0b99e58"
  }
}
---
# Harness Reset Product State

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
