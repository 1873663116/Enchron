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
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:c60cdd654e41002b2cf848afac7c4dc9c7743660f4596c97f195a4d9ba63bc26"
  }
}
---
# Accessibility Activate

The runtime Operation adapter accepts only its registered arguments and emits only its registered evidence pairs.
