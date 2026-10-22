---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-emby-server-lifecycle-emby-artwork-bypasses-loopback@1",
  "layer": 3,
  "role": "verification",
  "pace": "catalog",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
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
      "verb": "device.app-command",
      "args": {
        "verb": "setViewMode",
        "arguments": {
          "mode": "grid"
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
        "label": "Enchron Regression Emby"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Evidence"
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
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Evidence"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Home"
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

Emby Artwork 使用图片接口而非回环端点

Generated from `Config/regression/catalog-root/journeys/emby-server-lifecycle/scenarios/emby-artwork-bypasses-loopback.md`.
