---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:window-spatial-input:window-surface-controls-toggle-and-autohide",
  "title": "窗口空间输入切换并自动隐藏控件",
  "journey": "journey:window-spatial-input",
  "promiseRefs": [
    "promise:controls-summon:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "simulator",
  "estimatedCostMillis": 140000,
  "staticCases": [
    "three-toggle-sequence-and-autohide"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "window-input-fixture-ready",
      "schema": "fixture-set.window-input@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:03",
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
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:05",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450,
        "targetDomain": "canvas"
      },
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:06",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450,
        "targetDomain": "canvas"
      },
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:07",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "shotHeight": 900,
        "shotWidth": 1440,
        "shotX": 720,
        "shotY": 450,
        "targetDomain": "canvas"
      },
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:08",
      "maxInvocations": 1,
      "operation": "operation:input.device-hub-pinch@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:window-spatial-input:window-surface-controls-toggle-and-autohide:05/cursorToken",
        "settleDelayMillis": 9000
      },
      "callId": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "three-toggle-sequence-and-autohide",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:window-spatial-input:window-surface-controls-toggle-and-autohide:o01:three-toggle-sequence-and-autohide",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:window-spatial-input:window-surface-controls-toggle-and-autohide:09",
      "rubric": "rubric:window-spatial-input.window-surface-controls-toggle-and-autohide.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:window-spatial-input:window-surface-controls-toggle-and-autohide:o01:three-toggle-sequence-and-autohide"
  }
}
---
# 窗口空间输入切换并自动隐藏控件

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
