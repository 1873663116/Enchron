---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:playback.seek@2",
  "title": "Playback Seek",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "positionMillionths",
        "type": "integer",
        "required": true
      }
    ],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "playback.position"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:46beec247e912597e51e4f21f22b426c17c2d8a1ab7fbd84018fd4f3b24b83fd"
  }
}
---
# Playback Seek

The runtime Operation adapter adjusts the public PlayerPanel-progress Accessibility control to the requested normalized position and verifies that the same playback session, media identity, and content revision settle at the target.
