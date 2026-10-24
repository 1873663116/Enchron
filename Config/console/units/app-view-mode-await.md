---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:diagnostics.view-mode-await@1",
  "layer": 3,
  "role": "verification",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
  "actions": [
    {
      "verb": "device.session.ensure",
      "args": {
        "lane": "simulator"
      }
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": "test-media:TestVectors/Enchron/PlaybackBehavior/audio-only-aac-stereo-181s.m4a",
        "target": "view-mode-gate"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "view-mode-gate",
          "entry": "root"
        }
      }
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "list"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "FileBrowsing-FilesScreen-viewMode",
        "equals": "list",
        "timeoutMs": 10000,
        "intervalMs": 200
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "await.json",
    "schema": "enchron.console.await@1"
  },
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
          "name": "view-mode-gate"
        }
      }
    }
  ],
  "isolation": "clean-library"
}
---

Switch the library's view mode twice and wait for each change to land.
