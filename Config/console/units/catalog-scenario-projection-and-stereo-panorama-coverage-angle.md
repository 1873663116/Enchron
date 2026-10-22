---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-projection-and-stereo-panorama-coverage-angle@1",
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
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:Samples/Spatial/Stereo180/180_3D.mp4",
          "test-media:Samples/Spatial/Panorama/360.mp4",
          "test-media:Samples/Spatial/Stereo180/Apple-Streaming-Examples/APMP-180-example.mp4"
        ],
        "target": "scenario-projection-and-stereo-panorama-coverage-angle"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-projection-and-stereo-panorama-coverage-angle",
          "entry": "root"
        }
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-projection-and-stereo-panorama-coverage-angle"
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
        "identifier": "MediaLibrary-grid-video-180_3D.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "mediaName",
        "equals": "180_3D.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "applyFormat",
        "arguments": {
          "projection": "equirectangular180",
          "stereo": "sideBySide"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "projection",
        "equals": "equirectangular180",
        "timeoutMs": 30000,
        "intervalMs": 300
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-projection-and-stereo-panorama-coverage-angle"
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
        "identifier": "MediaLibrary-grid-video-360.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "mediaName",
        "equals": "360.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "applyFormat",
        "arguments": {
          "projection": "equirectangular360",
          "stereo": "mono"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "projection",
        "equals": "equirectangular360",
        "timeoutMs": 30000,
        "intervalMs": 300
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-projection-and-stereo-panorama-coverage-angle"
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
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "mediaName",
        "equals": "APMP-180-example.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "applyFormat",
        "arguments": {
          "projection": "customAngle",
          "stereo": "mono"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "projection",
        "equals": "customAngle",
        "timeoutMs": 30000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
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
          "name": "scenario-projection-and-stereo-panorama-coverage-angle"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "hierarchy.json",
    "schema": "enchron.console.hierarchy@1"
  }
}
---

180°、360° 与 Custom Angle 覆盖角

Generated from `Regression/journeys/projection-and-stereo/scenarios/panorama-coverage-angle.md`.
