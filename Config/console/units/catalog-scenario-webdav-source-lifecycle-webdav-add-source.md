---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-webdav-source-lifecycle-webdav-add-source@1",
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
      "verb": "device.source-facts",
      "args": {
        "provider": "webdav"
      },
      "capture": {
        "url": "webdavUrl",
        "username": "webdavUser",
        "password": "webdavPassword"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resetState",
        "arguments": {
          "keepSession": "true",
          "libraryFolder": "Journey Fixture"
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
          "directory": "scenario-webdav-source-lifecycle-webdav-add-source",
          "entry": "root"
        }
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-sourceMore",
          "FileBrowsing-SourcesSidebar-addWebDAV"
        ]
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "text": "Enchron Regression WebDAV"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "text": "$webdavUrl"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "text": "$webdavUser"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "text": "$webdavPassword"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-SourceConnection-webDAV-connect",
        "timeoutMs": 30000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tapEach",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect",
          "FileBrowsing-CertificateTrust-trust"
        ]
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 30000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "timeoutMs": 45000,
        "intervalMs": 400
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

通过产品表单添加 WebDAV 来源

Generated from `Regression/journeys/webdav-source-lifecycle/scenarios/webdav-add-source.md`.
