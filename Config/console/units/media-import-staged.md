---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:media.import-staged@1",
  "layer": 3,
  "role": "verification",
  "requires": ["mac", "device", "daemon"],
  "actions": [
    {"verb": "device.session.ensure", "args": {"lane": "simulator"}},
    {"verb": "device.stage-media", "args": {"source": "test-media:TestVectors/Enchron/PlaybackBehavior/audio-only-aac-stereo-181s.m4a", "target": "import-gate"}},
    {"verb": "device.app-command", "args": {"verb": "deleteLibraryFolder", "arguments": {"name": "import-gate"}}},
    {
      "verb": "device.app-command",
      "args": {"verb": "importStagedFolder", "arguments": {"directory": "import-gate", "entry": "root"}},
      "expect": {"path": "payload", "contains": "audio-only-aac-stereo-181s.m4a"}
    },
    {"verb": "device.command", "args": {"action": "tap", "identifier": "Navigation-Ornament-tab-files"}},
    {
      "verb": "device.snapshot",
      "args": {},
      "expect": {"path": "hierarchy", "contains": "MediaLibrary-grid-folder-import-gate"}
    }
  ],
  "terminal": {"kind": "artifact", "path": "hierarchy.json", "schema": "enchron.console.hierarchy@1"}
}
---

Stage one fixture, import it through the production pipeline, then confirm the library lists the folder.
