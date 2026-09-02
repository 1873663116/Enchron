---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:emby-server-lifecycle:series-season-episode-navigation",
  "title": "系列详情、季选择与剧集列表",
  "journey": "journey:emby-server-lifecycle",
  "promiseRefs": [
    "promise:emby-library:c02"
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
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:01",
      "maxInvocations": 1,
      "operation": "operation:host.preflight@1"
    },
    {
      "arguments": {},
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:02",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "emby"
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:03",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence"
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:04",
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
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Series, poster"
        ]
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence"
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "Emby-Season-Picker"
        ],
        "labels": [
          "Season 2"
        ],
        "labelsAfterIdentifiers": true
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:08",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence"
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "labels": [
          "Enchron Regression Episode 2, episode"
        ]
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "Emby-Evidence",
        "relatedResults": [
          "result://call:emby-server-lifecycle:series-season-episode-navigation:01/report",
          "result://call:emby-server-lifecycle:series-season-episode-navigation:07/response",
          "result://call:emby-server-lifecycle:series-season-episode-navigation:09/response"
        ]
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Emby-Home",
        "requireMatchedElement": true
      },
      "callId": "call:emby-server-lifecycle:series-season-episode-navigation:12",
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
      "id": "obligation:emby-server-lifecycle:series-season-episode-navigation:o01:default",
      "oracle": "oracle:agent-structured-emby-evidence@1",
      "producedByCall": "call:emby-server-lifecycle:series-season-episode-navigation:11",
      "rubric": "rubric:emby-server-lifecycle.series-season-episode-navigation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:emby-server-lifecycle:series-season-episode-navigation:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:emby-server-lifecycle:series-season-episode-navigation:12",
      "rubric": "rubric:emby-server-lifecycle.series-season-episode-navigation.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:emby-server-lifecycle:series-season-episode-navigation:o01:default"
      },
      {
        "observation": "obligation:emby-server-lifecycle:series-season-episode-navigation:o02:default"
      }
    ]
  }
}
---
# 系列详情、季选择与剧集列表

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
