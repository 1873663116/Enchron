---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.series-navigation@1",
  "layer": 3,
  "role": "verification",
  "pace": "slow",
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Navigation-Tab"
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
        "label": "Enchron Regression Emby"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Series, poster"
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "Emby-Evidence"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Emby-Season-Picker",
        "timeoutMs": 8000,
        "intervalMs": 250
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Season-Picker"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "label",
        "equals": "Season 2",
        "timeoutMs": 8000,
        "intervalMs": 250
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Season 2"
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
        "action": "swipeUp",
        "identifier": "Emby-Detail-list"
      }
    },
    {
      "verb": "device.await",
      "args": {
        "probe": "element",
        "field": "identifier",
        "equals": "Emby-Episode-11249",
        "timeoutMs": 6000,
        "intervalMs": 250
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "label": "Enchron Regression Episode 2, episode"
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

Open the regression series, switch to its second season and open an episode.
