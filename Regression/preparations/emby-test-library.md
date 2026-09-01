---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:emby-test-library",
  "title": "Prepare emby test library",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:emby-test-library:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "emby-aggregate"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:06",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "emby"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:07",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Connection-Address",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-adapters/Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
        "textJSONKey": "address",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:08",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Connection-Username",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-adapters/Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
        "textJSONKey": "username",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:09",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Connection-Password",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-adapters/Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json",
        "textJSONKey": "password",
        "secret": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:10",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Emby-Connection-Connect"
        ],
        "settleDelayMillis": 30000
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:11",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "以后"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:12",
      "operation": "operation:accessibility.inspect@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Home",
        "requireMatchedElement": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:emby-test-library:13",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "emby-aggregate"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "emby-test-library-ready",
      "schema": "remote-source.emby-library@2",
      "producedByCall": "call:preparation:emby-test-library:13",
      "dependsOnTags": [
        "app.session",
        "emby.account",
        "lane.instance",
        "source.connection",
        "source.emby",
        "source.emby.fixture-revision",
        "source.session"
      ]
    }
  ]
}
---
# Prepare emby test library

The runtime Preparation adapter validates the seeded Emby server, resets any persisted Emby account, enters the live runtime address and credentials through the public Emby connection form, dismisses the system Save-Password sheet that submitting those credentials raises, verifies the connected home screen, and produces reusable Emby library state.
