---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:viewing-state-and-storage:exit-saves-position",
  "title": "退出播放提交并保存当前位置",
  "journey": "journey:viewing-state-and-storage",
  "promiseRefs": [
    "promise:viewing-state:c01"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 330000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "viewing-storage-fixtures-ready",
      "schema": "fixture-set.viewing-storage@2"
    }
  ],
  "operations": [
    {
      "arguments": {
        "awaitEmptyStores": [
          "viewing-state"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:01",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Media Library"
        ]
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "viewing-storage-16m01s.mp4"
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:04",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:05",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:06",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "viewing-storage-16m01s.mp4",
        "minimumPositionMillis": 20000,
        "minimumRemainingMillis": 300000
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:07",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:exit-saves-position:01/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:08",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ],
        "summonControls": true
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:09",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:exit-saves-position:01/viewingStorageDigest",
          "result://call:viewing-state-and-storage:exit-saves-position:08/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:exit-saves-position:10",
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
      "id": "obligation:viewing-state-and-storage:exit-saves-position:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:viewing-state-and-storage:exit-saves-position:10",
      "rubric": "rubric:viewing-state-and-storage.exit-saves-position.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:viewing-state-and-storage:exit-saves-position:o01:default"
  }
}
---
# 退出播放提交并保存当前位置

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
