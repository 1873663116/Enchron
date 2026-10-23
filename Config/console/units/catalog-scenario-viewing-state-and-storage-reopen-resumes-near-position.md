---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-viewing-state-and-storage-reopen-resumes-near-position@1",
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
      "verb": "device.connect-source",
      "args": {
        "provider": "webdav",
        "name": "Enchron Regression WebDAV"
      }
    },
    {
      "verb": "device.stage-media",
      "args": {
        "source": [
          "test-media:TestVectors/Enchron/PlaybackBehavior/viewing-storage-16m01s.mp4",
          "test-media:TestVectors/Enchron/PlaybackBehavior/sdr-bframe-aggregate-30s.mkv"
        ],
        "target": "scenario-viewing-state-and-storage-reopen-resumes-near-position"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFolder",
        "arguments": {
          "directory": "scenario-viewing-state-and-storage-reopen-resumes-near-position",
          "entry": "root"
        }
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords1",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest1",
        "protectedStateDigest": "libraryProtectedDigest1",
        "snapshotDigest": "viewingStorageDigest1"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "viewing-storage",
        "field": "viewingStateRecordCount",
        "equals": "0",
        "timeoutMs": 30000,
        "intervalMs": 400
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
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "PlayerUI-window-control-plane",
        "mode": "absent",
        "timeoutMs": 15000,
        "intervalMs": 200
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "playMedia",
        "arguments": {
          "name": "viewing-storage-16m01s.mp4"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "viewing-storage-16m01s.mp4"
        },
        "timeoutMs": 90000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "seekNormalized",
        "arguments": {
          "position": "0.1"
        }
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 20.0,
        "mode": "atLeast",
        "timeoutMs": 90000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords8",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest8",
        "protectedStateDigest": "libraryProtectedDigest8",
        "snapshotDigest": "viewingStorageDigest8"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "toggleControls",
        "arguments": {
          "visible": "true"
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
        "verb": "resetMediaNavigation",
        "arguments": {}
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Navigation-Ornament-tab-files",
        "timeoutMs": 10000,
        "intervalMs": 200
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords10",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest10",
        "protectedStateDigest": "libraryProtectedDigest10",
        "snapshotDigest": "viewingStorageDigest10"
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
      "verb": "device.app-command",
      "args": {
        "verb": "leavePlayback",
        "arguments": {}
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
        "equals": "MediaLibrary-grid-folder-scenario-viewing-state-and-storage-reopen-resumes-near-position",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-folder-scenario-viewing-state-and-storage-reopen-resumes-near-position"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resolveResumePrompt",
        "arguments": {
          "action": "resume"
        }
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords15",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest15",
        "protectedStateDigest": "libraryProtectedDigest15",
        "snapshotDigest": "viewingStorageDigest15"
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
        "identifier": "FileBrowsing-SourcesSidebar-source-",
        "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
        "index": 1
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 20000,
        "intervalMs": 300
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
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
          "name": "scenario-viewing-state-and-storage-reopen-resumes-near-position"
        }
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  },
  "cases": [
    {
      "key": "default",
      "start": 6
    }
  ]
}
---

重新打开从保存位置续播

Generated from `Regression/journeys/viewing-state-and-storage/scenarios/reopen-resumes-near-position.md`.
