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
      "verb": "app.relaunch",
      "args": {}
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
        "label": "Enchron Regression WebDAV"
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Media Library"
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
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
        "equals": 20.0,
        "mode": "atLeast",
        "timeoutMs": 90000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.snapshot",
      "args": {}
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
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-resumeDecision-primary"
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

重新打开从保存位置续播

Generated from `Config/regression/catalog-root/journeys/viewing-state-and-storage/scenarios/reopen-resumes-near-position.md`.
