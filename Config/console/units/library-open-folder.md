---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:library.open-folder@1",
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
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "hierarchy.json",
    "schema": "enchron.console.hierarchy@1"
  },
  "isolation": "clean-library"
}
---

Opens the library surface and captures the accessibility hierarchy.
