---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:viewing-storage-fixtures-simulator",
  "title": "Prepare viewing storage fixtures simulator",
  "lane": "simulator",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-30s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:07",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-30s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:08",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:09",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-viewing-storage-h264-16m01s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:10",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-viewing-storage-h264-16m01s-b-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:11",
      "operation": "operation:storage.clear@1",
      "arguments": {
        "target": "container-index-cache"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:12",
      "operation": "operation:storage.clear@1",
      "arguments": {
        "target": "playback-progress"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:13",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "files"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:14",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-sourceMore",
          "FileBrowsing-SourcesSidebar-add",
          "FileBrowsing-SourcesSidebar-addWebDAV"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:15",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-name",
        "mode": "replace",
        "text": "Enchron Regression WebDAV",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:16",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-adapters/.build/regression-remote-source/runtime.json",
        "textJSONKey": "address",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:17",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-adapters/.build/regression-remote-source/runtime.json",
        "textJSONKey": "user",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:18",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/orca/workspace/Enchron/harness-adapters/.build/regression-remote-source/runtime.json",
        "textJSONKey": "password",
        "secret": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:19",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourceConnection-webDAV-connect"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:20",
      "operation": "operation:accessibility.activate@2",
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-CertificateTrust-trust"
        ]
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:21",
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
      "callId": "call:preparation:viewing-storage-fixtures-simulator:22",
      "operation": "operation:accessibility.inspect@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:viewing-storage-fixtures-simulator:23",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "viewing-storage-fixtures-ready",
      "schema": "fixture-set.viewing-storage@2",
      "producedByCall": "call:preparation:viewing-storage-fixtures-simulator:23",
      "dependsOnTags": [
        "app.session",
        "cache.state",
        "certificate.trust",
        "fixture.corpus",
        "lane.instance",
        "library.contents",
        "settings.state",
        "source.connection",
        "source.session",
        "source.webdav",
        "viewing.state"
      ]
    }
  ]
}
---
# Prepare viewing storage fixtures simulator

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
