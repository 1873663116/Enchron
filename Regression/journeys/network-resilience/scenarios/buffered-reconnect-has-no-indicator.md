---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:network-resilience:buffered-reconnect-has-no-indicator",
  "title": "缓冲充足时网络重连对用户无提示",
  "journey": "journey:network-resilience",
  "promiseRefs": [
    "promise:network-resilience:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 400000,
  "staticCases": [
    "paired-control",
    "buffer-absorbed-interruption"
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
      "arguments": {},
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:03",
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
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 3000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:05",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "healthy"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:06",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 6000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:07",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:buffered-reconnect-has-no-indicator:06/receiptID"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:08",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "expectation": "webdav-loopback",
        "minimumPositionMillis": 6000
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "productBindingDigest": "result://call:network-resilience:buffered-reconnect-has-no-indicator:09/bindingDigest",
        "remoteExpectation": "webdav-playback-range",
        "remoteGenerationToken": "result://call:network-resilience:buffered-reconnect-has-no-indicator:08/restoredGenerationToken"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:11",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:12",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:13",
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
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 3000,
        "minimumRemainingMillis": 10000
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:15",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "activate",
        "recipe": "buffer-absorbed-interruption"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:16",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 6000,
        "minimumRemainingMillis": 5000
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:17",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "check": "remote-faults",
        "phase": "restore",
        "receiptID": "result://call:network-resilience:buffered-reconnect-has-no-indicator:16/receiptID"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:18",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "expectation": "webdav-loopback",
        "minimumPositionMillis": 6000
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:19",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "productBindingDigest": "result://call:network-resilience:buffered-reconnect-has-no-indicator:19/bindingDigest",
        "relatedFrameManifests": [
          "result://call:network-resilience:buffered-reconnect-has-no-indicator:10/frameManifest"
        ],
        "remoteExpectation": "buffer-absorbed-interruption",
        "remoteReceiptID": "result://call:network-resilience:buffered-reconnect-has-no-indicator:16/receiptID",
        "restoredGenerationToken": "result://call:network-resilience:buffered-reconnect-has-no-indicator:18/restoredGenerationToken"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:20",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "productBindingDigest": "result://call:network-resilience:buffered-reconnect-has-no-indicator:19/bindingDigest",
        "relatedFrameManifests": [
          "result://call:network-resilience:buffered-reconnect-has-no-indicator:10/frameManifest"
        ],
        "remoteExpectation": "buffer-absorbed-interruption",
        "remoteReceiptID": "result://call:network-resilience:buffered-reconnect-has-no-indicator:16/receiptID",
        "restoredGenerationToken": "result://call:network-resilience:buffered-reconnect-has-no-indicator:18/restoredGenerationToken"
      },
      "callId": "call:network-resilience:buffered-reconnect-has-no-indicator:21",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "paired-control",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:network-resilience:buffered-reconnect-has-no-indicator:o01:paired-control",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:network-resilience:buffered-reconnect-has-no-indicator:20",
      "rubric": "rubric:network-resilience.buffered-reconnect-has-no-indicator.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "buffer-absorbed-interruption",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:network-resilience:buffered-reconnect-has-no-indicator:o01:buffer-absorbed-interruption",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:network-resilience:buffered-reconnect-has-no-indicator:21",
      "rubric": "rubric:network-resilience.buffered-reconnect-has-no-indicator.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:network-resilience:buffered-reconnect-has-no-indicator:o01:paired-control"
      },
      {
        "observation": "obligation:network-resilience:buffered-reconnect-has-no-indicator:o01:buffer-absorbed-interruption"
      }
    ]
  }
}
---
# 缓冲充足时网络重连对用户无提示

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
