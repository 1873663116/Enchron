---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:playback.format-apply@1",
  "layer": 3,
  "role": "verification",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
  "preconditions": [
    {
      "kind": "media-server",
      "provider": "emby"
    }
  ],
  "actions": [
    {
      "verb": "device.session.ensure",
      "args": {
        "lane": "simulator"
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv",
        "target": "format-media"
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "importStagedFolder",
            "arguments": {
              "directory": "format-media",
              "entry": "root"
            }
          },
          {
            "verb": "setViewMode",
            "arguments": {
              "mode": "grid"
            }
          }
        ]
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-files"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-format-media"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "mediaName",
        "equals": "sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 45000,
        "intervalMs": 500
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "toggleControls",
        "arguments": {
          "visible": "true"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "PlayerUI-TopAction-videoFormat"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapSequence",
        "identifiers": [
          "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side",
          "PlayerUI-VideoFormat-apply"
        ]
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "stereoLayout",
        "equals": "sideBySide",
        "timeoutMs": 30000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "toggleControls",
        "arguments": {
          "visible": "true"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "PlayerUI-TopAction-videoFormat"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapSequence",
        "identifiers": [
          "PlayerUI-VideoFormat-Stereo Layout-Mono",
          "PlayerUI-VideoFormat-apply"
        ]
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "stereoLayout",
        "equals": "mono",
        "timeoutMs": 30000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "format-media"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "hierarchy.json",
    "schema": "enchron.console.hierarchy@1"
  },
  "pace": "slow",
  "teardown": [
    {
      "verb": "device.app-command",
      "args": {
        "verb": "leavePlayback",
        "arguments": {}
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "format-media"
        }
      }
    }
  ]
}
---

Play one fixture, turn it into a 180-degree portal, then put it back to a flat window.
