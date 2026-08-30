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
    "digest": "sha256:bc027ea194114a53d77ceefcab18f000ec037dda33bd5c633ef5eb8360036399"
  }
}
---
# Playback Seek

The runtime Operation adapter adjusts the public PlayerPanel-progress Accessibility control to the requested normalized position and verifies that the same playback session, media identity, and content revision settle at the target.
