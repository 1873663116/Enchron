---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:diagnostics.probe-status@1",
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
      "verb": "device.app-command",
      "args": {
        "verb": "probeStatus"
      },
      "expect": {
        "path": "payload",
        "contains": "byteLimit="
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "app-command.json",
    "schema": "enchron.console.app-command@1"
  },
  "isolation": "clean-library"
}
---

Ask the app for its probe journal and confirm it answered with journal state.
