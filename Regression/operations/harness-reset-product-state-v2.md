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
    "digest": "sha256:d71725e8567bc710b16a8c0ac9304c09571bc4df01df1a1799500c4d49dd04a5"
  }
}
---
# Harness Reset Product State

The operation resets product state by removing library references and folders and deleting managed defaults. It requires that the requested library folder can be created when rootFolderName is provided; harness.reset-product-state requires active handling of folder creation and reports the product's folder creation error when it cannot. The handler enforces that folder creation must succeed, throwing the detail from mediaLibrary.lastErrorMessage when it does not, and verifies that exactly the declared number of folders and references were removed. It invalidates the declared tags and emits the typed product-state-reset receipt.
