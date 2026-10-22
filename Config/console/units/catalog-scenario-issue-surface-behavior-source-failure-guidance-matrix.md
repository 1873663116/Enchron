---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.scenario-issue-surface-behavior-source-failure-guidance-matrix@1",
  "layer": 3,
  "role": "verification",
  "pace": "catalog",
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
      "args": {
        "clean": true
      }
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
        "identifier": null
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "text": "Failure Matrix credentials-rejected"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": null
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-SourceConnection-webDAV-error"
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {
        "clean": true
      }
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
        "identifier": null
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "text": "Failure Matrix server-unreachable"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "text": "result://call:issue-surface-behavior:source-failure-guidance-matrix:11/unreachableAddress"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": null
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-SourceConnection-webDAV-error"
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {
        "clean": true
      }
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
        "identifier": null
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "text": "Failure Matrix invalid-address"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "text": "result://call:issue-surface-behavior:source-failure-guidance-matrix:21/missingPathAddress"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": null
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-SourceConnection-webDAV-error"
      }
    },
    {
      "verb": "app.relaunch",
      "args": {}
    },
    {
      "verb": "device.home",
      "args": {
        "clean": true
      }
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
        "identifier": null
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "text": "Failure Matrix requires-https"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "typeText",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "text": "result://call:issue-surface-behavior:source-failure-guidance-matrix:31/httpAddress"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password"
      }
    },
    {
      "verb": "device.command",
      "args": {
        "action": "tap",
        "identifier": null
      }
    },
    {
      "verb": "device.probe",
      "args": {
        "probe": "FileBrowsing-SourceConnection-webDAV-error"
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

凭据、主机与地址失败给出可区分下一步

Generated from `Config/regression/catalog-root/journeys/issue-surface-behavior/scenarios/source-failure-guidance-matrix.md`.
