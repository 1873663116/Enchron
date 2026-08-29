---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:clean-flat-playback-main-gate",
  "title": "干净基线平面播放 MainGate",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:clean-state-playback:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "both",
  "estimatedCostMillis": 122000,
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
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:01",
      "maxInvocations": 1,
      "operation": "operation:harness.reset-product-state@2"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:03",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:04",
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
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:local-media-lifecycle:clean-flat-playback-main-gate:07",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:local-media-lifecycle:clean-flat-playback-main-gate:o01:default",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:local-media-lifecycle:clean-flat-playback-main-gate:06",
      "rubric": "rubric:local-media-lifecycle.clean-flat-playback-main-gate.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:local-media-lifecycle:clean-flat-playback-main-gate:o02:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:local-media-lifecycle:clean-flat-playback-main-gate:07",
      "rubric": "rubric:local-media-lifecycle.clean-flat-playback-main-gate.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:local-media-lifecycle:clean-flat-playback-main-gate:o01:default"
      },
      {
        "observation": "obligation:local-media-lifecycle:clean-flat-playback-main-gate:o02:default"
      }
    ]
  },
  "mainGateFor": [
    "simulator",
    "device"
  ]
}
---
# 干净基线平面播放 MainGate

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
