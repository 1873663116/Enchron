---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-viewing-state-and-storage-remote-index-reused-on-second-open@1",
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
      "verb": "device.connect-source",
      "args": {
        "provider": "webdav",
        "name": "Enchron Regression WebDAV"
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
        "viewingStateRecordCount": "viewingRecords2",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest2",
        "protectedStateDigest": "libraryProtectedDigest2",
        "snapshotDigest": "viewingStorageDigest2"
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
        "identifier": "FileBrowsing-SourcesSidebar-source-",
        "identifierPrefix": "FileBrowsing-SourcesSidebar-source-",
        "index": 1
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
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "presentation",
        "equals": "window",
        "timeoutMs": 90000,
        "intervalMs": 400
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
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords9",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest9",
        "protectedStateDigest": "libraryProtectedDigest9",
        "snapshotDigest": "viewingStorageDigest9"
      }
    },
    {
      "verb": "device.app-commands",
      "args": {
        "calls": [
          {
            "verb": "toggleControls",
            "arguments": {
              "visible": "true"
            }
          },
          {
            "verb": "leavePlayback",
            "arguments": {}
          }
        ]
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords11",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest11",
        "protectedStateDigest": "libraryProtectedDigest11",
        "snapshotDigest": "viewingStorageDigest11"
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
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "presentation",
        "equals": "window",
        "timeoutMs": 90000,
        "intervalMs": 400
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
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  }
}
---

远程文件第二次打开复用容器索引

Generated from `Regression/journeys/viewing-state-and-storage/scenarios/remote-index-reused-on-second-open.md`.
