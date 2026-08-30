---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:presentation-fixtures-simulator",
  "title": "Prepare presentation fixtures simulator",
  "lane": "simulator",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:presentation-fixtures-simulator:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:07",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:08",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-180-sbs-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:09",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "180_3D.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:10",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-360-mono-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:11",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "360.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:12",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:13",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:14",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "files"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:15",
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
      "callId": "call:preparation:presentation-fixtures-simulator:16",
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
      "callId": "call:preparation:presentation-fixtures-simulator:17",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-address",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.build/regression-remote-source/runtime.json",
        "textJSONKey": "address",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:18",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-username",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.build/regression-remote-source/runtime.json",
        "textJSONKey": "user",
        "secret": false
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:19",
      "operation": "operation:accessibility.type@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-SourceConnection-webDAV-password",
        "mode": "replace",
        "textFile": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/Enchron/.build/regression-remote-source/runtime.json",
        "textJSONKey": "password",
        "secret": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:20",
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
      "callId": "call:preparation:presentation-fixtures-simulator:21",
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
      "callId": "call:preparation:presentation-fixtures-simulator:22",
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
      "callId": "call:preparation:presentation-fixtures-simulator:23",
      "operation": "operation:accessibility.inspect@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-simulator:24",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2",
      "producedByCall": "call:preparation:presentation-fixtures-simulator:24",
      "dependsOnTags": [
        "app.session",
        "certificate.trust",
        "fixture.corpus",
        "lane.instance",
        "library.contents",
        "presentation.state",
        "source.connection",
        "source.session",
        "source.webdav"
      ]
    }
  ]
}
---
# Prepare presentation fixtures simulator

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
