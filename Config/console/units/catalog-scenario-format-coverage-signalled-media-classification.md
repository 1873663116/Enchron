---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-format-coverage-signalled-media-classification@1",
  "layer": 3,
  "role": "verification",
  "pace": "scenario",
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
        "verb": "resetState",
        "arguments": {
          "keepSession": "true"
        }
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
          "test-media:Samples/Spatial/Stereo180/Apple-Streaming-Examples/APMP-180-example.mp4",
          "test-media:Samples/Spatial/MVHEVC-Apple-Official/spatial_lighthouse_flowers_waves_short.mov"
        ],
        "target": "scenario-format-coverage-signalled-media-classification"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-format-coverage-signalled-media-classification",
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
        "identifier": "MediaLibrary-grid-folder-scenario-format-coverage-signalled-media-classification"
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
        "equals": "MediaLibrary-grid-video-APMP-180-example.mp4",
        "timeoutMs": 20000,
        "intervalMs": 400
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
        "probe": "element",
        "field": "identifier",
        "equals": "WindowPlayback-root",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
        "intervalMs": 1000
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
        "identifier": "MediaLibrary-grid-folder-scenario-format-coverage-signalled-media-classification"
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
        "equals": "MediaLibrary-grid-video-spatial_lighthouse_flowers_waves_short.mov",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-spatial_lighthouse_flowers_waves_short.mov"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "spatial_lighthouse_flowers_waves_short.mov"
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
        "timeoutMs": 45000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
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
          "name": "scenario-format-coverage-signalled-media-classification"
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

带信令媒体按来源声明选择呈现

Generated from `Regression/journeys/format-coverage/scenarios/signalled-media-classification.md`.
