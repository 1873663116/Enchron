---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:diagnostics.view-mode@1",
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
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "view-mode-gate"
        }
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
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-FilesScreen-viewMode"
      },
      "expect": {
        "path": "matchedElement.identifier",
        "equals": "FileBrowsing-FilesScreen-viewMode"
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  },
  "teardown": [
    {
      "verb": "device.app-command",
      "args": {
        "verb": "deleteLibraryFolder",
        "arguments": {
          "name": "view-mode-gate"
        }
      }
    }
  ]
}
---

Read the library's view-mode control by identifier.
