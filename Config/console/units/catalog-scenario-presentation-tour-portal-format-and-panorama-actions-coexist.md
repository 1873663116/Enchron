---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-presentation-tour-portal-format-and-panorama-actions-coexist@1",
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
          "test-media:Samples/Spatial/Stereo180/180_3D.mp4",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv"
        ],
        "target": "scenario-presentation-tour-portal-format-and-panorama-actions-coexist"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-presentation-tour-portal-format-and-panorama-actions-coexist",
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
      "verb": "device.app-command",
      "args": {
        "verb": "playMedia",
        "arguments": {
          "name": "180_3D.mp4"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "WindowPlayback-root",
        "timeoutMs": 45000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "PlayerUI-window-playback-surface"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
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
          "name": "scenario-presentation-tour-portal-format-and-panorama-actions-coexist"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  }
}
---

Portal 同时提供格式编辑与 Enter Panorama

Generated from `Regression/journeys/presentation-tour/scenarios/portal-format-and-panorama-actions-coexist.md`.
