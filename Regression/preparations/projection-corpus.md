---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:projection-corpus",
  "title": "Prepare projection corpus",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:projection-corpus:01",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:02",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:03",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:04",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:05",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-dolby-vision-p20-3d-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:06",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "3D-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:07",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-180-sbs-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:08",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "180_3D.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:09",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-180-tb-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:10",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "180_3D_TB.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:11",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-spatial-360-mono-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:12",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "360.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:13",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-mvhevc-short-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:14",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "spatial_lighthouse_flowers_waves_short.mov"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:15",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-apmp-180-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:16",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "APMP-180-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:17",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-apmp-360-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:18",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "APMP-360-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:19",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-immersive-video-beach-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:20",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "Immersive-Video-example.f99766.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:21",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:22",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:23",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:projection-corpus:24",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "projection-corpus-ready",
      "schema": "fixture-set.projection-stereo@2",
      "producedByCall": "call:preparation:projection-corpus:24",
      "dependsOnTags": [
        "app.session",
        "display.capture",
        "fixture.corpus",
        "lane.instance",
        "library.contents"
      ]
    }
  ]
}
---
# Prepare projection corpus

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
