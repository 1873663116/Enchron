---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:dynamic-range-interpretation:docked-hlg-audio-integrity",
  "title": "HLG 文件进入 Docked 后音频保持存活",
  "journey": "journey:dynamic-range-interpretation",
  "promiseRefs": [
    "promise:track-selection:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 150000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "dynamic-range-corpus-ready",
      "schema": "fixture-set.dynamic-range@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-hlg-hevc-10bit-avsync-10s.mp4"
      },
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:03",
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
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:05",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "summonControls": true
      },
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:06",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-docked-skybox@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:07",
      "maxInvocations": 1,
      "operation": "operation:harness.assert-channels@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:dynamic-range-interpretation:docked-hlg-audio-integrity:05/fields"
        ]
      },
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:08",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "durationMillis": 5000,
        "expectedSession": "result://call:dynamic-range-interpretation:docked-hlg-audio-integrity:05/session",
        "inputDevice": "Steinberg UR12",
        "wavPath": "audio/docked-hlg-audio-integrity-default.wav"
      },
      "callId": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:09",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-audio@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:dynamic-range-interpretation:docked-hlg-audio-integrity:o01:default",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:08",
      "rubric": "rubric:dynamic-range-interpretation.docked-hlg-audio-integrity.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "audio-measurement@2",
      "evidenceType": "audio.measurement",
      "id": "obligation:dynamic-range-interpretation:docked-hlg-audio-integrity:o02:default",
      "oracle": "oracle:agent-audio@2",
      "producedByCall": "call:dynamic-range-interpretation:docked-hlg-audio-integrity:09",
      "rubric": "rubric:dynamic-range-interpretation.docked-hlg-audio-integrity.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:dynamic-range-interpretation:docked-hlg-audio-integrity:o01:default"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:docked-hlg-audio-integrity:o02:default"
      }
    ]
  }
}
---
# HLG 文件进入 Docked 后音频保持存活

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
