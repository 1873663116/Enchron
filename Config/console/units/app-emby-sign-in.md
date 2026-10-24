---
{
  "schema": "enchron.console.unit",
  "schemaVersion": 1,
  "id": "unit:app.emby-sign-in@1",
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

Sign the application back in to the media server using a digest an earlier step captured.
