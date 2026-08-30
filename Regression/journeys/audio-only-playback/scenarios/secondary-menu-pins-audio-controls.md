---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:audio-only-playback:secondary-menu-pins-audio-controls",
  "title": "纯音频二级菜单钉住最小控件集",
  "journey": "journey:audio-only-playback",
  "promiseRefs": [
    "promise:controls-summon:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 228000,
  "staticCases": [
    "audio-menu",
    "speed-menu"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "audio-only-fixtures-ready",
      "schema": "fixture-set.audio-only@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-inside.m4a"
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:03",
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
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:05",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerPanel-menu-more",
          "PlayerPanel-menu-audio"
        ]
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:audio-only-playback:secondary-menu-pins-audio-controls:05/cursorToken",
        "settleDelayMillis": 9000
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:07",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {},
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:08",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:09",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-inside.m4a"
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:10",
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
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:11",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:12",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerPanel-menu-more",
          "PlayerPanel-menu-speed"
        ]
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:audio-only-playback:secondary-menu-pins-audio-controls:05/cursorToken",
        "settleDelayMillis": 9000
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:14",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "cursorToken": "result://call:audio-only-playback:secondary-menu-pins-audio-controls:05/cursorToken",
        "settleDelayMillis": 9000
      },
      "callId": "call:audio-only-playback:secondary-menu-pins-audio-controls:15",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "audio-menu",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:audio-only-playback:secondary-menu-pins-audio-controls:o01:audio-menu",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:audio-only-playback:secondary-menu-pins-audio-controls:14",
      "rubric": "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "speed-menu",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:audio-only-playback:secondary-menu-pins-audio-controls:o01:speed-menu",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:audio-only-playback:secondary-menu-pins-audio-controls:15",
      "rubric": "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:audio-only-playback:secondary-menu-pins-audio-controls:o01:audio-menu"
      },
      {
        "observation": "obligation:audio-only-playback:secondary-menu-pins-audio-controls:o01:speed-menu"
      }
    ]
  }
}
---
# 纯音频二级菜单钉住最小控件集

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
