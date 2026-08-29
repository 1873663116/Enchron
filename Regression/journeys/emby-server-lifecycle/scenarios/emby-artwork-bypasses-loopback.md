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
  "estimatedCostMillis": 65000,
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
      "arguments": {},
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Root"
      },
      "callId": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:emby-server-lifecycle:emby-artwork-bypasses-loopback:o01:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:emby-server-lifecycle:emby-artwork-bypasses-loopback:03",
      "rubric": "rubric:emby-server-lifecycle.emby-artwork-bypasses-loopback.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:emby-server-lifecycle:emby-artwork-bypasses-loopback:o01:default"
  }
}
---
# Emby Artwork 使用图片接口而非回环端点

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
