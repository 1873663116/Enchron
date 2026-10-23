---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-viewing-state-and-storage-storage-rows-report-and-clear@1",
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
    },
    {
      "kind": "media-source",
      "provider": "webdav"
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
        "target": "scenario-viewing-state-and-storage-storage-rows-report-and-clear"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "importStagedFiles",
        "arguments": {
          "directory": "scenario-viewing-state-and-storage-storage-rows-report-and-clear"
        }
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-settings"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-SettingsScreen",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-category-storagePrivacy",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-category-storagePrivacy",
        "waitMilliseconds": 800
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-action-clear-artwork-cache",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-action-clear-artwork-cache"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-action-clear-container-index-cache",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-action-clear-container-index-cache"
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords3",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest3",
        "protectedStateDigest": "libraryProtectedDigest3",
        "snapshotDigest": "viewingStorageDigest3"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "viewing-storage",
        "field": "containerIndexEntryCount",
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourcesSidebar-source-",
        "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
        "index": 1
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "equals": {
          "presentation": "window",
          "mediaName": "sdr-bframe-aggregate-30s.mkv"
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
        "equals": 3.0,
        "mode": "atLeast",
        "timeoutMs": 90000,
        "intervalMs": 400
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
        "viewingStateRecordCount": "viewingRecords17",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest17",
        "protectedStateDigest": "libraryProtectedDigest17",
        "snapshotDigest": "viewingStorageDigest17"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Navigation-Ornament-tab-settings"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-category-storagePrivacy"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Settings-StoragePrivacy-group"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-action-clear-artwork-cache",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-action-clear-artwork-cache"
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords22",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest22",
        "protectedStateDigest": "libraryProtectedDigest22",
        "snapshotDigest": "viewingStorageDigest22"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Settings-StoragePrivacy-group"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Settings-action-clear-container-index-cache",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Settings-action-clear-container-index-cache"
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords25",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest25",
        "protectedStateDigest": "libraryProtectedDigest25",
        "snapshotDigest": "viewingStorageDigest25"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "viewing-storage",
        "field": "containerIndexEntryCount",
        "equals": "0",
        "timeoutMs": 30000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Settings-StoragePrivacy-group"
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords27",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest27",
        "protectedStateDigest": "libraryProtectedDigest27",
        "snapshotDigest": "viewingStorageDigest27"
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
          "name": "scenario-viewing-state-and-storage-storage-rows-report-and-clear"
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

两条存储行分别报数并清除

Generated from `Regression/journeys/viewing-state-and-storage/scenarios/storage-rows-report-and-clear.md`.
