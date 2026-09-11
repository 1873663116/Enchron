---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:emby-server-lifecycle:episode-resume-and-start-actions",
  "title": "单集详情页的单一 Play 入口与 Resume Playback? alert 的两个选择",
  "journey": "journey:emby-server-lifecycle",
  "promiseRefs": [
    "promise:emby-library:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 240000,
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
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:03",
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
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "deadlineSeconds": 15,
        "identifier": "Emby-Detail-Play",
        "requireMatchedElement": true
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Emby-Detail-Play"
        ]
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "PlayerUI-resumeDecision-primary"
        ]
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:08",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:10",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ],
        "summonControls": true
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:11",
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
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:12",
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
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:13",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:14",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence",
        "relatedResults": [
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:01/report",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:05/matchedElement",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:06/response",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:07/activatedAtMonotonicMillis",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:08/elapsedMillis",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:09/fields",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:10/frames",
          "result://call:emby-server-lifecycle:episode-resume-and-start-actions:14/fields"
        ]
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:15",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Home",
        "requireMatchedElement": true
      },
      "callId": "call:emby-server-lifecycle:episode-resume-and-start-actions:16",
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
      "id": "obligation:emby-server-lifecycle:episode-resume-and-start-actions:o01:default",
      "oracle": "oracle:agent-structured-emby-evidence@1",
      "producedByCall": "call:emby-server-lifecycle:episode-resume-and-start-actions:15",
      "rubric": "rubric:emby-server-lifecycle.episode-resume-and-start-actions.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:emby-server-lifecycle:episode-resume-and-start-actions:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:emby-server-lifecycle:episode-resume-and-start-actions:16",
      "rubric": "rubric:emby-server-lifecycle.episode-resume-and-start-actions.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:emby-server-lifecycle:episode-resume-and-start-actions:o01:default"
      },
      {
        "observation": "obligation:emby-server-lifecycle:episode-resume-and-start-actions:o02:default"
      }
    ]
  }
}
---
# 单集详情页的单一 Play 入口与 Resume Playback? alert 的两个选择

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
