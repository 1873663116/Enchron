---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:local-aggregate-device",
  "title": "Prepare local aggregate device",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:local-aggregate-device:01",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:02",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:03",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:04",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:05",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-30s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-30s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:07",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-external-subrip-zh-cn-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:08",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-aggregate-external-ass-styled-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:09",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-subtitles-30s-v3",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:10",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:11",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:local-aggregate-device:12",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-viewing-storage-h264-16m01s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2",
      "producedByCall": "call:preparation:local-aggregate-device:12",
      "dependsOnTags": [
        "app.session",
        "fixture.corpus",
        "lane.instance"
      ]
    }
  ]
}
---
# Prepare local aggregate device

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
