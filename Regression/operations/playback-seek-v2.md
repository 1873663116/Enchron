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
    "digest": "sha256:65e1419b109ee9171294e01fb5f49ae6acfbbca612dc63764bd1bbc686df0622"
  }
}
---
# Playback Seek

The runtime Operation adapter adjusts the public PlayerPanel-progress Accessibility control to the requested normalized position and verifies that the same playback session, media identity, and content revision settle at the target.
