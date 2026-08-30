---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:spatial-controls-summon",
  "title": "Docked 与 Panorama 空间外壳召唤控件",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:controls-summon:c02"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "simulator",
  "estimatedCostMillis": 570000,
  "staticCases": [
    "docked-show",
    "docked-hide",
    "panorama-show",
    "panorama-hide"
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
      "callId": "call:presentation-tour:spatial-controls-summon:01",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-prepare@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:04",
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
      "callId": "call:presentation-tour:spatial-controls-summon:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:spatial-controls-summon:06",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-docked-skybox@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:07",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450
      },
      "callId": "call:presentation-tour:spatial-controls-summon:08",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:presentation-tour:spatial-controls-summon:07/cursorToken"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:10",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:11",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:12",
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
      "callId": "call:presentation-tour:spatial-controls-summon:13",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:spatial-controls-summon:14",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-docked-skybox@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:15",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450
      },
      "callId": "call:presentation-tour:spatial-controls-summon:16",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450
      },
      "callId": "call:presentation-tour:spatial-controls-summon:17",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:presentation-tour:spatial-controls-summon:15/cursorToken"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:18",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:19",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:20",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:21",
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
      "callId": "call:presentation-tour:spatial-controls-summon:22",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:23",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:spatial-controls-summon:24",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-panorama@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:25",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450
      },
      "callId": "call:presentation-tour:spatial-controls-summon:26",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:presentation-tour:spatial-controls-summon:25/cursorToken"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:27",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:28",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:29",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:30",
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
      "callId": "call:presentation-tour:spatial-controls-summon:31",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:32",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:spatial-controls-summon:33",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-panorama@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:spatial-controls-summon:34",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450
      },
      "callId": "call:presentation-tour:spatial-controls-summon:35",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450
      },
      "callId": "call:presentation-tour:spatial-controls-summon:36",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:presentation-tour:spatial-controls-summon:34/cursorToken"
      },
      "callId": "call:presentation-tour:spatial-controls-summon:37",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "docked-show",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:presentation-tour:spatial-controls-summon:o01:docked-show",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:presentation-tour:spatial-controls-summon:09",
      "rubric": "rubric:presentation-tour.spatial-controls-summon.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "docked-hide",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:presentation-tour:spatial-controls-summon:o01:docked-hide",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:presentation-tour:spatial-controls-summon:18",
      "rubric": "rubric:presentation-tour.spatial-controls-summon.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "panorama-show",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:presentation-tour:spatial-controls-summon:o01:panorama-show",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:presentation-tour:spatial-controls-summon:27",
      "rubric": "rubric:presentation-tour.spatial-controls-summon.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "panorama-hide",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:presentation-tour:spatial-controls-summon:o01:panorama-hide",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:presentation-tour:spatial-controls-summon:37",
      "rubric": "rubric:presentation-tour.spatial-controls-summon.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:spatial-controls-summon:o01:docked-show"
      },
      {
        "observation": "obligation:presentation-tour:spatial-controls-summon:o01:docked-hide"
      },
      {
        "observation": "obligation:presentation-tour:spatial-controls-summon:o01:panorama-show"
      },
      {
        "observation": "obligation:presentation-tour:spatial-controls-summon:o01:panorama-hide"
      }
    ]
  }
}
---
# Docked 与 Panorama 空间外壳召唤控件

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
