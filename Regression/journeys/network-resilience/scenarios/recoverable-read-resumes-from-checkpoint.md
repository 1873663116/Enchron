---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:network-resilience:recoverable-read-resumes-from-checkpoint",
  "title": "可恢复读失败与流结束分离",
  "journey": "journey:network-resilience",
  "promiseRefs": [
    "promise:network-resilience:c02"
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
    "single-read-failure"
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
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:01",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:02",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:03",
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
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 5000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:06",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "recoverable-read-interruption"
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:07",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/mediaName",
        "minimumPositionMillis": 8000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:08",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "expectation": "recoverable-read",
        "expectedContentRevision": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/contentRevision",
        "expectedSession": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/session",
        "expectedSourceIdentity": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/sourceIdentity",
        "expectedTopologyDigest": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/topologyDigest",
        "minimumPositionMillis": 8000,
        "minimumReconnects": 1
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:07/receiptID"
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:10",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "productBindingDigest": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:09/bindingDigest",
        "relatedResults": [
          "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/fields",
          "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:06/session",
          "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:09/fields",
          "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:09/expectationObservation",
          "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:09/binding"
        ],
        "remoteExpectation": "recoverable-read",
        "remoteReceiptID": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:07/receiptID",
        "restoredGenerationToken": "result://call:network-resilience:recoverable-read-resumes-from-checkpoint:10/restoredGenerationToken"
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:11",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:network-resilience:recoverable-read-resumes-from-checkpoint:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "single-read-failure",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:network-resilience:recoverable-read-resumes-from-checkpoint:o01:single-read-failure",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:network-resilience:recoverable-read-resumes-from-checkpoint:11",
      "rubric": "rubric:network-resilience.recoverable-read-resumes-from-checkpoint.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "single-read-failure",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:network-resilience:recoverable-read-resumes-from-checkpoint:o02:single-read-failure",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:network-resilience:recoverable-read-resumes-from-checkpoint:13",
      "rubric": "rubric:network-resilience.recoverable-read-resumes-from-checkpoint.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:network-resilience:recoverable-read-resumes-from-checkpoint:o01:single-read-failure"
      },
      {
        "observation": "obligation:network-resilience:recoverable-read-resumes-from-checkpoint:o02:single-read-failure"
      }
    ]
  }
}
---
# 可恢复读失败与流结束分离

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
