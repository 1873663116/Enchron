---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:clean-start-position-zero",
  "title": "干净状态从零位置起播",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:clean-state-playback:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 120000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "callId": "call:local-media-lifecycle:clean-start-position-zero:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:clean-start-position-zero:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:local-media-lifecycle:clean-start-position-zero:03",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:local-media-lifecycle:clean-start-position-zero:04",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:local-media-lifecycle:clean-start-position-zero:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:clean-start-position-zero:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:local-media-lifecycle:clean-start-position-zero:o01:default",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:local-media-lifecycle:clean-start-position-zero:06",
      "rubric": "rubric:local-media-lifecycle.clean-start-position-zero.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:local-media-lifecycle:clean-start-position-zero:o01:default"
  }
}
---
# 干净状态从零位置起播

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
