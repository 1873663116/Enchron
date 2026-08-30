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
    "digest": "sha256:62e8b68e2824de74f8b2e2bf5c30dcffb0d4faf88ffe8cba81d325e202e6ed7c"
  }
}
---
# Playback Seek

The runtime Operation adapter adjusts the public PlayerPanel-progress Accessibility control to the requested normalized position and verifies that the same playback session, media identity, and content revision settle at the target.
