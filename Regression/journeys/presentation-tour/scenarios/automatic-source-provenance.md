---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:automatic-source-provenance",
  "title": "Automatic 在来源格式时禁用并显示选中",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:format-editing:c03"
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
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:presentation-tour:automatic-source-provenance:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:automatic-source-provenance:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "either-main-window",
        "identifier": "MediaLibrary-grid-video-APMP-180-example.mp4"
      },
      "callId": "call:presentation-tour:automatic-source-provenance:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:presentation-tour:automatic-source-provenance:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "flat",
        "stereoLayout": "mono",
        "summonControls": true
      },
      "callId": "call:presentation-tour:automatic-source-provenance:05",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "context": "window",
        "dismissControls": true,
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-automatic",
          "PlayerUI-VideoFormat-apply"
        ]
      },
      "callId": "call:presentation-tour:automatic-source-provenance:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:presentation-tour:automatic-source-provenance:05/before",
          "result://call:presentation-tour:automatic-source-provenance:05/after",
          "result://call:presentation-tour:automatic-source-provenance:06/response"
        ],
        "settleDelayMillis": 2000
      },
      "callId": "call:presentation-tour:automatic-source-provenance:07",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:presentation-tour:automatic-source-provenance:o01:default",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:presentation-tour:automatic-source-provenance:07",
      "rubric": "rubric:presentation-tour.automatic-source-provenance.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:presentation-tour:automatic-source-provenance:o01:default"
  }
}
---
# Automatic 在来源格式时禁用并显示选中

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
