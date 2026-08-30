---
{
  "schema": "enchron.regression.operation",
  "schemaVersion": 1,
  "id": "operation:playback.select-subtitle@1",
  "title": "Playback Select Subtitle",
  "role": "product-behavior",
  "lanes": [
    "device",
    "simulator"
  ],
  "argumentSchema": {
    "fields": [
      {
        "name": "host",
        "type": "string",
        "required": true
      },
      {
        "name": "sourceKind",
        "type": "string",
        "required": true
      },
      {
        "name": "trackLabel",
        "type": "string",
        "required": false
      },
      {
        "name": "deadlineSeconds",
        "type": "integer",
        "required": true
      }
    ],
    "rules": [],
    "additionalProperties": false
  },
  "invalidatesTags": [
    "playback.selection",
    "ui.state"
  ],
  "evidenceSchemas": [
    {
      "evidenceType": "window.control-plane",
      "evidenceSchema": "window-control-plane@1"
    }
  ],
  "implementation": {
    "locator": "Scripts/verification/regression_operation_adapter.py",
    "digest": "sha256:00d8e78cf5a88b70b8bf9d6bff760cfc5bae3f9d312e88b31c4feb3389928d56"
  }
}
---
# Playback Select Subtitle

The runtime Operation adapter selects one external subtitle through the public PlayerUI host in one controller transaction: PlayerUI-window-playback-surface, PlayerUI-TopAction-more, PlayerUI-menu-subtitles, and PlayerUI-menu-subtitles-external.subtitle.* items. host admits only playerUI, the host that can produce the declared window.control-plane pair after product.md:17 removes that window probe from an immersive settle. It then verifies the same playback identity and selected track in product state.
