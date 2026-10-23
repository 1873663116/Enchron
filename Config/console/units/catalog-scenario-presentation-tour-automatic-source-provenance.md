---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-presentation-tour-automatic-source-provenance@1",
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
          "test-media:Samples/Spatial/Stereo180/Apple-Streaming-Examples/APMP-180-example.mp4",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv"
        ],
        "target": "scenario-presentation-tour-automatic-source-provenance"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-presentation-tour-automatic-source-provenance",
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
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "applyFormat",
            "arguments": {
              "projection": "flat",
              "stereo": "mono"
            }
          },
          {
            "verb": "reapplyFormat",
            "arguments": {}
          }
        ]
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
          "name": "scenario-presentation-tour-automatic-source-provenance"
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

Automatic 在来源格式时禁用并显示选中

Generated from `Regression/journeys/presentation-tour/scenarios/automatic-source-provenance.md`.
