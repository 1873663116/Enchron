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
      },
      {
        "name": "summonControls",
        "type": "boolean",
        "required": false
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "playback.position"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:2aca7cf32430446cf0e8e30832a2fbe3fc9653e8f05004679721c834e0b99e58"
  }
}
---
# Playback Seek

The runtime Operation adapter taps the public PlayerPanel-progress track at the requested normalized offset through the controller's coordinateTap action, which the panel's single SpatialTapGesture routes to seekToTrack; it requires the product's own progress.seekToTrack probe line for every tap, corrects the residual left by the thumb-inset affine up to five times, and verifies that the same playback session, media identity and content revision settle at the target position. The progress bar's accessibilityAdjustableAction is a fixed fifteen-second step with a textual value and no normalized position, and the drag state machine is wearer-only, so neither is used.
