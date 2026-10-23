---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-emby-server-lifecycle-artwork-by-image-tag@1",
  "layer": 3,
  "role": "verification",
  "pace": "scenario",
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
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {}
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "resetMediaNavigation",
        "arguments": {}
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Navigation-Tab"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Sidebar-home"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Emby"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "label",
        "equals": "Enchron Regression Emby",
        "timeoutMs": 20000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Emby"
      }
    },
    {
      "verb": "device.viewing-storage",
      "args": {},
      "capture": {
        "viewingStateRecordCount": "viewingRecords5",
        "viewingStateProtectedStateDigest": "viewingProtectedDigest5",
        "protectedStateDigest": "libraryProtectedDigest5",
        "snapshotDigest": "viewingStorageDigest5"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Evidence"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Root"
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

Emby 封面按 image tag 落盘

Generated from `Regression/journeys/emby-server-lifecycle/scenarios/artwork-by-image-tag.md`.
