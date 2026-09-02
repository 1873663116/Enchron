---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:emby-server-lifecycle:emby-artwork-bypasses-loopback",
  "title": "Emby Artwork 使用图片接口而非回环端点",
  "journey": "journey:emby-server-lifecycle",
  "promiseRefs": [
    "promise:cache-and-artwork:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 100000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "emby-test-library-ready",
      "schema": "remote-source.emby-library@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "check": "emby-aggregate"
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "window",
        "deadlineSeconds": 20,
        "identifier": "Emby-Evidence",
        "requireMatchedElement": true
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Series, poster"
        ],
        "settleDelayMillis": 20000
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence",
        "relatedResults": [
          "result://call:emby-server-lifecycle:emby-artwork-bypasses-loopback:01/report"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Home",
        "requireMatchedElement": true
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "emby-evidence@1",
      "evidenceType": "emby.evidence",
      "id": "obligation:emby-server-lifecycle:emby-artwork-bypasses-loopback:o01:default",
      "oracle": "oracle:agent-structured-emby-evidence@1",
      "producedByCall": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:06",
      "rubric": "rubric:emby-server-lifecycle.emby-artwork-bypasses-loopback.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:emby-server-lifecycle:emby-artwork-bypasses-loopback:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:07",
      "rubric": "rubric:emby-server-lifecycle.emby-artwork-bypasses-loopback.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:emby-server-lifecycle:emby-artwork-bypasses-loopback:o01:default"
      },
      {
        "observation": "obligation:emby-server-lifecycle:emby-artwork-bypasses-loopback:o02:default"
      }
    ]
  }
}
---
# Emby Artwork 使用图片接口而非回环端点

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
