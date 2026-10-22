---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:evidence.capture-frames@1",
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
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.capture-frames",
      "args": {
        "count": 3,
        "intervalMs": 100
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "frames.json",
    "schema": "enchron.console.frames@1"
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

Capture three frames of the library and keep them in the run's evidence.
