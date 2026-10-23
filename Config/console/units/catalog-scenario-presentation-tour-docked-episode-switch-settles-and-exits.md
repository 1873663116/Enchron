---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-presentation-tour-docked-episode-switch-settles-and-exits@1",
  "layer": 3,
  "role": "verification",
  "pace": "catalog",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
  "isolation": "clean-library",
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
      "verb": "device.app-command",
      "args": {
        "verb": "leavePlayback",
        "arguments": {}
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resetState",
        "arguments": {
          "keepSession": "true"
        }
      }
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-120s.mp4",
          "test-media:Samples/Spatial/Stereo180/180_3D.mp4"
        ],
        "target": "scenario-presentation-tour-docked-episode-switch-settles-and-exits"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-presentation-tour-docked-episode-switch-settles-and-exits",
          "entry": "root"
        }
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
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "PlayerUI-window-control-plane",
        "mode": "absent",
        "timeoutMs": 15000,
        "intervalMs": 200
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "playMedia",
        "arguments": {
          "name": "sdr-bframe-multiaudio-avsync-120s.mp4"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "sdr-bframe-multiaudio-avsync-120s.mp4"
        },
        "timeoutMs": 45000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "presentation",
        "equals": "window",
        "timeoutMs": 30000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "enterSpatial",
        "arguments": {
          "environment": "quiet-room"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "PlayerPanel-button-exit-spatial",
        "timeoutMs": 30000,
        "intervalMs": 400
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
        "action": "tapEach",
        "identifiers": [
          "PlayerPanel-menu-more",
          "PlayerPanel-menu-episodes"
        ]
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "label",
        "equals": "180_3D.mp4",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "180_3D.mp4"
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 1,
        "intervalMs": 1000
      }
    }
  ],
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
          "name": "scenario-presentation-tour-docked-episode-switch-settles-and-exits"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "frames.json",
    "schema": "enchron.console.frames@1"
  },
  "cases": [
    {
      "key": "default",
      "start": 5
    }
  ]
}
---

Docked 内切换到全景剧集时退出 Dock 落到 portal

Generated from `Regression/journeys/presentation-tour/scenarios/docked-episode-switch-settles-and-exits.md`.
