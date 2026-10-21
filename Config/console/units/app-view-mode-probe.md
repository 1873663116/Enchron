---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:diagnostics.view-mode@1",
  "layer": 3,
  "role": "verification",
  "requires": ["mac", "device", "daemon"],
  "actions": [
    {"verb": "device.session.ensure", "args": {"lane": "simulator"}},
    {
      "verb": "device.probe",
      "args": {"probe": "FileBrowsing-FilesScreen-viewMode"},
      "expect": {
        "path": "matchedElement.identifier",
        "equals": "FileBrowsing-FilesScreen-viewMode"
      }
    }
  ],
  "terminal": {"kind": "artifact", "path": "probe.json", "schema": "enchron.console.probe@1"}
}
---

Read the library's view-mode control by identifier.
