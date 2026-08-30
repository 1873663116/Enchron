---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:accessibility.activate@2",
  "title": "Accessibility Activate",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "context",
        "type": "string",
        "required": true
      },
      {
        "name": "identifiers",
        "type": "string-list",
        "required": false
      },
      {
        "name": "labels",
        "type": "string-list",
        "required": false
      },
      {
        "name": "index",
        "type": "integer",
        "required": false
      },
      {
        "name": "gesture",
        "type": "string",
        "required": false
      },
      {
        "name": "durationMillis",
        "type": "integer",
        "required": false
      },
      {
        "name": "settleDelayMillis",
        "type": "integer",
        "required": false
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "cache.state",
    "certificate.trust",
    "issue.surface",
    "library.contents",
    "media.format",
    "playback.position",
    "playback.selection",
    "playback.session",
    "presentation.state",
    "renderer.graph",
    "settings.state",
    "source.session",
    "ui.navigation",
    "ui.state",
    "viewing.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "accessibility.tree",
      "evidenceSchema": "accessibility-tree@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:62e8b68e2824de74f8b2e2bf5c30dcffb0d4faf88ffe8cba81d325e202e6ed7c"
  }
}
---
# Accessibility Activate

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
