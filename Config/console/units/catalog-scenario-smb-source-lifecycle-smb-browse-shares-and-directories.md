---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-smb-source-lifecycle-smb-browse-shares-and-directories@1",
  "layer": 3,
  "role": "verification",
  "pace": "scenario",
  "requires": [
    "mac",
    "device",
    "daemon"
  ],
  "preconditions": [
    {
      "kind": "media-source",
      "provider": "smb"
    }
  ],
  "isolation": "clean-library",
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
      "verb": "device.snapshot",
      "args": {}
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "MediaLibrary-grid-video-sdr-bframe-aggregate-30s.mkv"
      }
    }
  ],
  "teardown": [],
  "terminal": {
    "kind": "artifact",
    "path": "probe.json",
    "schema": "enchron.console.probe@1"
  }
}
---

SMB 共享与目录逐层浏览

Generated from `Config/regression/catalog-root/journeys/smb-source-lifecycle/scenarios/smb-browse-shares-and-directories.md`.
