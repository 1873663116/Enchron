---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-emby-server-lifecycle-episode-resume-and-start-actions@1",
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
        "identifier": "Emby-Episode-",
        "identifierPrefix": "Emby-Episode-",
        "waitMilliseconds": 1200
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-window-control-plane"
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
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-window-control-plane"
      }
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
        "intervalMs": 1000
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
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "Emby-Episode-",
        "identifierPrefix": "Emby-Episode-",
        "waitMilliseconds": 1200
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "seekNormalized",
        "arguments": {
          "position": "0"
        }
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
      "verb": "device.probe",
      "args": {
        "probe": "PlayerUI-window-control-plane"
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

单集详情页的单一 Play 入口与 Resume Playback? alert 的两个选择

Generated from `Config/regression/catalog-root/journeys/emby-server-lifecycle/scenarios/episode-resume-and-start-actions.md`.
