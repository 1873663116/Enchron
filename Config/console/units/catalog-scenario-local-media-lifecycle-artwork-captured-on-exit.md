---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-local-media-lifecycle-artwork-captured-on-exit@1",
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
      "verb": "app.relaunch",
      "args": {}
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
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv"
        ],
        "target": "scenario-local-media-lifecycle-artwork-captured-on-exit"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-local-media-lifecycle-artwork-captured-on-exit",
          "entry": "root"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-settings"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-SettingsScreen",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-category-storagePrivacy",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-category-storagePrivacy",
        "waitMilliseconds": 800
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-action-clear-artwork-cache",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-action-clear-artwork-cache"
      }
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-FilesScreen",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-local-media-lifecycle-artwork-captured-on-exit"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 20000,
        "intervalMs": 400
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
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 5.0,
        "mode": "atLeast",
        "timeoutMs": 90000,
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
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "lifecycle",
        "equals": "Playing",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 4,
        "intervalMs": 0
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "toggleControls",
            "arguments": {
              "visible": "true"
            }
          },
          {
            "verb": "leavePlayback",
            "arguments": {}
          }
        ]
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 4,
        "intervalMs": 0
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 20000,
        "intervalMs": 400
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
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 22.0,
        "mode": "atLeast",
        "timeoutMs": 90000,
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
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "lifecycle",
        "equals": "Playing",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 4,
        "intervalMs": 0
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "toggleControls",
            "arguments": {
              "visible": "true"
            }
          },
          {
            "verb": "leavePlayback",
            "arguments": {}
          }
        ]
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 4,
        "intervalMs": 0
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
          "name": "scenario-local-media-lifecycle-artwork-captured-on-exit"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "frames.json",
    "schema": "enchron.console.frames@1"
  }
}
---

退出播放时用当前画面更新 Artwork

Generated from `Regression/journeys/local-media-lifecycle/scenarios/artwork-captured-on-exit.md`.
