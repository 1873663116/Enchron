---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:presentation-fixtures-device",
  "title": "Prepare presentation fixtures device",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:presentation-fixtures-device:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "webdav-regression"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:07",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:08",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-180-sbs-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:09",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "180_3D.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:10",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-360-mono-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:11",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "360.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:12",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-dolby-vision-p20-3d-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:13",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "3D-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:14",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-180-tb-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:15",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "180_3D_TB.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:16",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-mvhevc-short-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:17",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "spatial_lighthouse_flowers_waves_short.mov"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:18",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-apmp-180-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:19",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "APMP-180-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:20",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-apmp-360-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:21",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "APMP-360-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:22",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-immersive-video-beach-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:23",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "Immersive-Video-example.f99766.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:24",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:25",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:26",
      "operation": "operation:navigation.select-tab@1",
      "arguments": {
        "tab": "files"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:27",
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
      "callId": "call:preparation:presentation-fixtures-device:28",
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
      "callId": "call:preparation:presentation-fixtures-device:29",
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
      "callId": "call:preparation:presentation-fixtures-device:30",
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
      "callId": "call:preparation:presentation-fixtures-device:31",
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
      "callId": "call:preparation:presentation-fixtures-device:32",
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
      "callId": "call:preparation:presentation-fixtures-device:33",
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
      "callId": "call:preparation:presentation-fixtures-device:34",
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
      "callId": "call:preparation:presentation-fixtures-device:35",
      "operation": "operation:accessibility.inspect@2",
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:presentation-fixtures-device:36",
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
      "producedByCall": "call:preparation:presentation-fixtures-device:36",
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
# Prepare presentation fixtures device

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
