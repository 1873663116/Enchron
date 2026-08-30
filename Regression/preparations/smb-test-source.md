---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:smb-test-source",
  "title": "Prepare smb test source",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:smb-test-source:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "smb-aggregate"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:06",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "files"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:07",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-sourceMore",
          "FileBrowsing-SourcesSidebar-add",
          "FileBrowsing-SourcesSidebar-addSMB"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:08",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-smb-name",
        "mode": "replace",
        "text": "Enchron Regression SMB",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:09",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-smb-address",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.build/regression-smb-source/runtime.json",
        "textJSONKey": "address",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:10",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-smb-username",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.build/regression-smb-source/runtime.json",
        "textJSONKey": "user",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:11",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-smb-password",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.build/regression-smb-source/runtime.json",
        "textJSONKey": "password",
        "secret": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:12",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-smb-connect"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:13",
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
      "callId": "call:preparation:smb-test-source:14",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-grid-folder-TestMedia"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:15",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-grid-folder-TestVectors"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:16",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-grid-folder-Enchron"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:17",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-grid-folder-PlaybackBehavior"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:18",
      "operation": "operation:accessibility.inspect@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:smb-test-source:19",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "smb-aggregate"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "smb-test-source-ready",
      "schema": "remote-source.smb-fixture@2",
      "producedByCall": "call:preparation:smb-test-source:19",
      "dependsOnTags": [
        "app.session",
        "fixture.corpus",
        "lane.instance",
        "source.session"
      ]
    }
  ]
}
---
# Prepare smb test source

The runtime Preparation adapter validates the SMB fixture service, establishes an authenticated product source session through the public connection UI, verifies the fixture hierarchy and media, and produces reusable source.session state.
