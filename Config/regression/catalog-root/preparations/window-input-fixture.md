---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:window-input-fixture",
  "title": "Prepare window input fixture",
  "lane": "simulator",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:window-input-fixture:01",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:02",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:03",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:04",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:05",
      "operation": "operation:input.device-hub-prepare@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:06",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-avsync-120s-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:07",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:08",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:window-input-fixture:09",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "window-input-fixture-ready",
      "schema": "fixture-set.window-input@2",
      "producedByCall": "call:preparation:window-input-fixture:09",
      "dependsOnTags": [
        "app.session",
        "fixture.corpus",
        "input.device-hub",
        "lane.instance",
        "library.contents",
        "settings.state"
      ]
    }
  ]
}
---
# Prepare window input fixture

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
