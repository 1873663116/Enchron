---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-library-management-move-references@1",
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
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-multiaudio-avsync-30s.mp4"
        ],
        "target": "scenario-library-management-move-references"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resetState",
        "arguments": {
          "keepSession": "true",
          "libraryFolder": "Regression Destination"
        }
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFiles",
        "arguments": {
          "directory": "scenario-library-management-move-references"
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourcesSidebar-source-media-library"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-Manage-button",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-Manage-button"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "MediaLibrary-Manage-selectMultiple",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-Manage-selectMultiple"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "MediaLibrary-MultiSelect-move",
        "timeoutMs": 15000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-MultiSelect-move"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "label",
        "equals": "Regression Destination",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Regression Destination"
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
          "name": "scenario-library-management-move-references"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "hierarchy.json",
    "schema": "enchron.console.hierarchy@1"
  },
  "cases": [
    {
      "key": "default",
      "start": 4
    }
  ]
}
---

Move references

Generated from `Regression/journeys/library-management/scenarios/move-references.md`.
