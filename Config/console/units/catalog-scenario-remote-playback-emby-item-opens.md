---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:catalog.remote-playback-emby-item-opens@1",
  "layer": 3,
  "role": "verification",
  "pace": "slow",
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
  "actions": [
    {
      "verb": "device.session.ensure",
      "args": {
        "lane": "simulator"
      }
    },
    {
      "verb": "device.stage-identity",
      "args": {
        "source": "Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json"
      },
      "capture": {
        "digest": "identityDigest"
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "embySignIn",
        "arguments": {
          "identityDigest": "$identityDigest"
        }
      },
      "expect": {
        "path": "embySignInReceipt.persisted",
        "equals": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "playServerItem",
        "arguments": {
          "name": "Alien: Covenant"
        }
      },
      "expect": {
        "path": "ok",
        "equals": true
      }
    },
    {
      "verb": "device.app-command",
      "args": {
        "verb": "playbackProbe",
        "arguments": {}
      }
    }
  ],
  "terminal": {
    "kind": "artifact",
    "path": "app-command.json",
    "schema": "enchron.console.app-command@1"
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

Open a title from the signed-in media server and read the playback probe, so a remote item that fails to start is visible in the console record rather than only in a manual run.
