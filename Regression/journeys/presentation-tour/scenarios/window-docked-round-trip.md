---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:window-docked-round-trip",
  "title": "Window 与 Docked 双向切换",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:mode-transitions:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 180000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:presentation-tour:window-docked-round-trip:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:window-docked-round-trip:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:window-docked-round-trip:03",
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
      "callId": "call:presentation-tour:window-docked-round-trip:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:window-docked-round-trip:05",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.arm@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:window-docked-round-trip:06",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-docked-skybox@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "from": "docked"
      },
      "callId": "call:presentation-tour:window-docked-round-trip:07",
      "maxInvocations": 1,
      "operation": "operation:presentation.exit-spatial@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:window-docked-round-trip:05/generationToken"
      },
      "callId": "call:presentation-tour:window-docked-round-trip:08",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.fetch@1"
    },
    {
      "arguments": {
        "generationToken": "result://call:presentation-tour:window-docked-round-trip:05/generationToken"
      },
      "callId": "call:presentation-tour:window-docked-round-trip:09",
      "maxInvocations": 1,
      "operation": "operation:transition-trace.disarm@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "transition-trace@1",
      "evidenceType": "transition.trace",
      "id": "obligation:presentation-tour:window-docked-round-trip:o01:default",
      "oracle": "oracle:agent-structured-transition@1",
      "producedByCall": "call:presentation-tour:window-docked-round-trip:08",
      "rubric": "rubric:presentation-tour.window-docked-round-trip.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:presentation-tour:window-docked-round-trip:o01:default"
  }
}
---
# Window 与 Docked 双向切换

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
