---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:network-resilience:finite-backoff-reconnect",
  "title": "断线后执行有限退避且引擎不主动断开",
  "journey": "journey:network-resilience",
  "promiseRefs": [
    "promise:network-resilience:c03"
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
      "callId": "call:network-resilience:finite-backoff-reconnect:01",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:02",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:03",
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
      "callId": "call:network-resilience:finite-backoff-reconnect:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 5000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:finite-backoff-reconnect:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "finite-reconnect"
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:07",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "result://call:network-resilience:finite-backoff-reconnect:06/mediaName",
        "minimumPositionMillis": 8000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:08",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "expectation": "finite-reconnect",
        "expectedContentRevision": "result://call:network-resilience:finite-backoff-reconnect:06/contentRevision",
        "expectedSession": "result://call:network-resilience:finite-backoff-reconnect:06/session",
        "expectedSourceIdentity": "result://call:network-resilience:finite-backoff-reconnect:06/sourceIdentity",
        "expectedTopologyDigest": "result://call:network-resilience:finite-backoff-reconnect:06/topologyDigest",
        "minimumPositionMillis": 8000,
        "minimumReconnects": 3
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:finite-backoff-reconnect:07/receiptID"
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:11",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "productBindingDigest": "result://call:network-resilience:finite-backoff-reconnect:09/bindingDigest",
        "remoteExpectation": "finite-backoff",
        "remoteReceiptID": "result://call:network-resilience:finite-backoff-reconnect:07/receiptID",
        "restoredGenerationToken": "result://call:network-resilience:finite-backoff-reconnect:11/restoredGenerationToken"
      },
      "callId": "call:network-resilience:finite-backoff-reconnect:12",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:network-resilience:finite-backoff-reconnect:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:network-resilience:finite-backoff-reconnect:12",
      "rubric": "rubric:network-resilience.finite-backoff-reconnect.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:network-resilience:finite-backoff-reconnect:o01:default"
  }
}
---
# 断线后执行有限退避且引擎不主动断开

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
