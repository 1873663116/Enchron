---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:audio-only-fixtures",
  "title": "Prepare audio only fixtures",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:audio-only-fixtures:01",
      "operation": "operation:host.preflight@1",
      "arguments": {
        "check": "audio-fixtures"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:02",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:03",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:04",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:05",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-alac-cover-art-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:07",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "inside.m4a"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:08",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-dts-es-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:09",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "dts_es.dts"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:10",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-truehd-atmos-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:11",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "atmos.thd"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:12",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-vorbis-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:13",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "1.0-test_small.ogg"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:14",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:audio-only-fixtures:15",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "audio-only-fixtures-ready",
      "schema": "fixture-set.audio-only@2",
      "producedByCall": "call:preparation:audio-only-fixtures:15",
      "dependsOnTags": [
        "app.session",
        "fixture.corpus",
        "lane.instance",
        "library.contents"
      ]
    }
  ]
}
---
# Prepare audio only fixtures

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
