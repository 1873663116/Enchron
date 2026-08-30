---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:emby-server-lifecycle:progress-authority-server",
  "title": "Emby 播放进度写回服务器",
  "journey": "journey:emby-server-lifecycle",
  "promiseRefs": [
    "promise:emby-library:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 165000,
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
      "callId": "call:emby-server-lifecycle:progress-authority-server:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence"
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Emby"
        ]
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Series"
        ]
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Episode"
        ]
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:07",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "minimumPositionMillis": 15000,
        "minimumRemainingMillis": 30000
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:08",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:progress-authority-server:09",
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
      "callId": "call:emby-server-lifecycle:progress-authority-server:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:11",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence"
      },
      "callId": "call:emby-server-lifecycle:progress-authority-server:12",
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
      "id": "obligation:emby-server-lifecycle:progress-authority-server:o01:default",
      "oracle": "oracle:agent-structured-emby-evidence@1",
      "producedByCall": "call:emby-server-lifecycle:progress-authority-server:12",
      "rubric": "rubric:emby-server-lifecycle.progress-authority-server.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:emby-server-lifecycle:progress-authority-server:o01:default"
  }
}
---
# Emby 播放进度写回服务器

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
