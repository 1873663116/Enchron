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
    "playback.position",
    "ui.state"
  ],
  "evidenceSchemas": [],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:ed10e583b4e69fa6fdad2cf7047126cf19166f9c7971ae55eb03cc7ac975ea6e"
  }
}
---
# Playback Seek

The runtime Operation adapter taps the public PlayerPanel-progress track at the requested normalized offset through the controller's coordinateTap action, which the panel's single SpatialTapGesture routes to seekToTrack; it requires the product's own progress.seekToTrack probe line for every tap, corrects the residual left by the thumb-inset affine up to five times, and verifies that the same playback session, media identity and content revision settle at the target position. The progress bar's accessibilityAdjustableAction is a fixed fifteen-second step with a textual value and no normalized position, and the drag state machine is wearer-only, so neither is used.
