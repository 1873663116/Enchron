---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-network-resilience-prefetch-without-waiting-consumer@1",
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
        "target": "scenario-network-resilience-prefetch-without-waiting-consumer"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFiles",
        "arguments": {
          "directory": "scenario-network-resilience-prefetch-without-waiting-consumer"
        }
      }
    },
    {
      "verb": "static.structural-test",
      "args": {
        "check": "playback-core-network-resilience"
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
          "name": "scenario-network-resilience-prefetch-without-waiting-consumer"
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

无阻塞消费者时仍预取至水位线

Generated from `Regression/journeys/network-resilience/scenarios/prefetch-without-waiting-consumer.md`.
