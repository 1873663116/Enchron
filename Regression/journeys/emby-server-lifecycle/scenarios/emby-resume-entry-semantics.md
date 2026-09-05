---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:emby-server-lifecycle:emby-resume-entry-semantics",
  "title": "Emby Resume 尊重服务器位置而从头播放忽略它",
  "journey": "journey:emby-server-lifecycle",
  "promiseRefs": [
    "promise:viewing-state:c04"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 210000,
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
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Episode, episode"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Emby-Detail-Play",
          "PlayerUI-resumeDecision-primary"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:05",
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
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:06",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:07",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Emby-Detail-Play",
          "PlayerUI-resumeDecision-secondary"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:09",
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
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:10",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:11",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence",
        "relatedResults": [
          "result://call:emby-server-lifecycle:emby-resume-entry-semantics:01/report",
          "result://call:emby-server-lifecycle:emby-resume-entry-semantics:07/fields",
          "result://call:emby-server-lifecycle:emby-resume-entry-semantics:11/fields"
        ]
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Home",
        "requireMatchedElement": true
      },
      "callId": "call:emby-server-lifecycle:emby-resume-entry-semantics:14",
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
      "id": "obligation:emby-server-lifecycle:emby-resume-entry-semantics:o01:default",
      "oracle": "oracle:agent-structured-emby-evidence@1",
      "producedByCall": "call:emby-server-lifecycle:emby-resume-entry-semantics:13",
      "rubric": "rubric:emby-server-lifecycle.emby-resume-entry-semantics.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:emby-server-lifecycle:emby-resume-entry-semantics:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:emby-server-lifecycle:emby-resume-entry-semantics:14",
      "rubric": "rubric:emby-server-lifecycle.emby-resume-entry-semantics.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:emby-server-lifecycle:emby-resume-entry-semantics:o01:default"
      },
      {
        "observation": "obligation:emby-server-lifecycle:emby-resume-entry-semantics:o02:default"
      }
    ]
  }
}
---
# Emby Resume 尊重服务器位置而从头播放忽略它

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
