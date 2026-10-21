---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:network-resilience:certificate-change-stops-without-trust",
  "title": "播放中证书变化单列且不现场接受",
  "journey": "journey:network-resilience",
  "promiseRefs": [
    "promise:network-resilience:c06"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 390000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "faultable-remote-source-ready",
      "schema": "remote-source.faultable@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:01",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:02",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "either-main-window"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 5000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:certificate-change-stops-without-trust:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "certificate-rotation"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:07",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "paused",
        "presentation": "either-main-window"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:08",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:certificate-change-stops-without-trust:07/receiptID"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:09",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "cursorToken": "result://call:network-resilience:certificate-change-stops-without-trust:06/cursorToken",
        "remoteExpectation": "certificate-change",
        "remoteReceiptID": "result://call:network-resilience:certificate-change-stops-without-trust:07/receiptID",
        "restoredGenerationToken": "result://call:network-resilience:certificate-change-stops-without-trust:09/restoredGenerationToken"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:10",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-loadFailure-secondary"
        ]
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "cursorToken": "result://call:network-resilience:certificate-change-stops-without-trust:06/cursorToken",
        "relatedResults": [
          "result://call:network-resilience:certificate-change-stops-without-trust:10/fields"
        ],
        "remoteExpectation": "certificate-change",
        "remoteReceiptID": "result://call:network-resilience:certificate-change-stops-without-trust:07/receiptID",
        "restoredGenerationToken": "result://call:network-resilience:certificate-change-stops-without-trust:09/restoredGenerationToken"
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:12",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:network-resilience:certificate-change-stops-without-trust:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:network-resilience:certificate-change-stops-without-trust:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:network-resilience:certificate-change-stops-without-trust:12",
      "rubric": "rubric:network-resilience.certificate-change-stops-without-trust.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:network-resilience:certificate-change-stops-without-trust:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:network-resilience:certificate-change-stops-without-trust:13",
      "rubric": "rubric:network-resilience.certificate-change-stops-without-trust.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:network-resilience:certificate-change-stops-without-trust:o01:default"
      },
      {
        "observation": "obligation:network-resilience:certificate-change-stops-without-trust:o02:default"
      }
    ]
  }
}
---
# 播放中证书变化单列且不现场接受

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
