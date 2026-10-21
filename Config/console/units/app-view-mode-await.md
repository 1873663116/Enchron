---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:diagnostics.view-mode-await@1",
  "layer": 3,
  "role": "verification",
  "requires": ["mac", "device", "daemon"],
  "actions": [
    {"verb": "device.session.ensure", "args": {"lane": "simulator"}},
    {"verb": "device.app-command", "args": {"verb": "setViewMode", "arguments": {"mode": "list"}}},
    {"verb": "device.await", "args": {"probe": "FileBrowsing-FilesScreen-viewMode", "equals": "list", "timeoutMs": 10000, "intervalMs": 200}},
    {"verb": "device.app-command", "args": {"verb": "setViewMode", "arguments": {"mode": "grid"}}},
    {"verb": "device.await", "args": {"probe": "FileBrowsing-FilesScreen-viewMode", "equals": "grid", "timeoutMs": 10000, "intervalMs": 200}}
  ],
  "terminal": {"kind": "artifact", "path": "await.json", "schema": "enchron.console.await@1"}
}
---

Switch the library's view mode twice and wait for each change to land.
