---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-format-coverage-audio-retirement-on-failure@1",
  "layer": 3,
  "role": "verification",
  "pace": "catalog",
  "requires": [
    "daemon",
    "device",
    "mac",
    "python",
    "xcode"
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
      "verb": "static.structural-test",
      "args": {
        "check": "audio-retirement-open"
      }
    },
    {
      "verb": "static.structural-test",
      "args": {
        "check": "audio-retirement-prewarm"
      }
    },
    {
      "verb": "static.structural-test",
      "args": {
        "check": "audio-retirement-playback"
      }
    },
    {
      "verb": "static.structural-test",
      "args": {
        "check": "audio-retirement-seek"
      }
    },
    {
      "verb": "static.structural-test",
      "args": {
        "check": "audio-retirement-renderer"
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
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "hierarchy.json",
    "schema": "enchron.console.hierarchy@1"
  }
}
---

音轨在各失败阶段退休后视频仍可继续

Generated from `Regression/journeys/format-coverage/scenarios/audio-retirement-on-failure.md`.
