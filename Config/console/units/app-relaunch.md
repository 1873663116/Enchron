---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:app.relaunch@1",
  "layer": 3,
  "role": "verification",
  "requires": [
    "mac",
    "device",
    "daemon"
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
      "verb": "device.snapshot",
      "args": {},
      "expect": {
        "path": "appState",
        "equals": "runningForeground"
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "hierarchy.json",
    "schema": "enchron.console.hierarchy@1"
  },
  "isolation": "clean-library",
  "teardown": [
    {
      "verb": "device.app-command",
      "args": {
        "verb": "leavePlayback",
        "arguments": {}
      }
    }
  ]
}
---

Relaunch the app and confirm it publishes its hierarchy again.
