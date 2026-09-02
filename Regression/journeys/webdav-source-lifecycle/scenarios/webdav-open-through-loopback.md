---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:webdav-source-lifecycle:webdav-open-through-loopback",
  "title": "WebDAV 卡片经回环端点进入播放",
  "journey": "journey:webdav-source-lifecycle",
  "promiseRefs": [
    "promise:remote-source-connection:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 360000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "webdav-test-source-ready",
      "schema": "remote-source.webdav-fixture@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "webdav-regression"
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "deadlineSeconds": 45,
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "either-main-window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:05",
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
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:06",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "minimumPositionMillis": 3000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:07",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "expectation": "webdav-loopback",
        "minimumPositionMillis": 3000
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:08",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000,
        "productBindingDigest": "result://call:webdav-source-lifecycle:webdav-open-through-loopback:08/bindingDigest",
        "remoteExpectation": "webdav-playback-range",
        "remoteGenerationToken": "result://call:webdav-source-lifecycle:webdav-open-through-loopback:01/generationToken"
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:09",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:webdav-source-lifecycle:webdav-open-through-loopback:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "frame-sequence@2",
      "evidenceType": "visual.frames",
      "id": "obligation:webdav-source-lifecycle:webdav-open-through-loopback:o01:default",
      "oracle": "oracle:agent-visual@2",
      "producedByCall": "call:webdav-source-lifecycle:webdav-open-through-loopback:09",
      "rubric": "rubric:webdav-source-lifecycle.webdav-open-through-loopback.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:webdav-source-lifecycle:webdav-open-through-loopback:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:webdav-source-lifecycle:webdav-open-through-loopback:10",
      "rubric": "rubric:webdav-source-lifecycle.webdav-open-through-loopback.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:webdav-source-lifecycle:webdav-open-through-loopback:o01:default"
      },
      {
        "observation": "obligation:webdav-source-lifecycle:webdav-open-through-loopback:o02:default"
      }
    ]
  }
}
---
# WebDAV 卡片经回环端点进入播放

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
