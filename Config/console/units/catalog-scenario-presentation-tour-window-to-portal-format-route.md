---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-presentation-tour-window-to-portal-format-route@1",
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
      "verb": "device.connect-source",
      "args": {
        "provider": "webdav",
        "name": "Enchron Regression WebDAV"
      }
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-120s.mp4",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv"
        ],
        "target": "scenario-presentation-tour-window-to-portal-format-route"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-presentation-tour-window-to-portal-format-route",
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
        "equals": "FileBrowsing-FilesScreen",
        "timeoutMs": 20000,
        "intervalMs": 400
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
      "verb": "device.app-command",
      "args": {
        "verb": "armTransitionTrace",
        "arguments": {}
      },
      "capture": {
        "generation": "traceGeneration1"
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "applyFormat",
            "arguments": {
              "projection": "equirectangular180",
              "stereo": "mono"
            }
          },
          {
            "verb": "fetchTransitionTraceSnapshot",
            "arguments": {
              "generation": "$traceGeneration1"
            }
          },
          {
            "verb": "disarmTransitionTrace",
            "arguments": {
              "generation": "$traceGeneration1"
            }
          }
        ]
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
        "equals": "FileBrowsing-FilesScreen",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourcesSidebar-source-",
        "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
        "index": 1
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
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
          "name": "scenario-presentation-tour-window-to-portal-format-route"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  },
  "cases": [
    {
      "key": "default",
      "start": 6
    }
  ]
}
---

应用全景格式从 window 路由到 portal

Generated from `Regression/journeys/presentation-tour/scenarios/window-to-portal-format-route.md`.
