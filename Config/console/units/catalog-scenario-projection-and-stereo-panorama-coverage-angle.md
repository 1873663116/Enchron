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
      "verb": "device.app-command",
      "args": {
        "verb": "playMedia",
        "arguments": {
          "name": "360.mp4"
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
      "verb": "device.app-command",
      "args": {
        "verb": "playMedia",
        "arguments": {
          "name": "APMP-180-example.mp4"
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
      "verb": "device.app-command",
      "args": {
        "verb": "playMedia",
        "arguments": {
          "name": "APMP-180-example.mp4"
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
