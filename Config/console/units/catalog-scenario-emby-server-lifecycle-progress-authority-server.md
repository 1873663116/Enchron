---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-emby-server-lifecycle-progress-authority-server@1",
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
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Evidence"
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
        "label": "Enchron Regression Emby"
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Series, poster",
        "labelPrefix": "Enchron Regression Series"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Series, poster",
        "labelPrefix": "Enchron Regression Series"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Episode-",
        "identifierPrefix": "Emby-Episode-",
        "waitMilliseconds": 1200
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "presentation",
        "equals": "window",
        "timeoutMs": 45000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "PlayerUI-window-control-plane",
        "field": "position",
        "equals": 12.0,
        "mode": "atLeast",
        "timeoutMs": 45000,
        "intervalMs": 400
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-window-control-plane"
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "PlayerUI-InfoBar-button-back"
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

Emby 播放进度写回服务器

Generated from `Config/regression/catalog-root/journeys/emby-server-lifecycle/scenarios/progress-authority-server.md`.
