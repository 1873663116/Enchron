---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:viewing-state-and-storage:completed-media-starts-from-beginning",
  "title": "看完标记与之后从头播放",
  "journey": "journey:viewing-state-and-storage",
  "promiseRefs": [
    "promise:viewing-state:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 510000,
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
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:01",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:02",
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
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "viewing-storage-16m01s-b.mp4"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:04",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s-b.mp4"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:05",
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
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:06",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "positionMillionths": 997000,
        "summonControls": true
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:07",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "ended",
        "presentation": "window"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:08",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:01/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:09",
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
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:01/viewingStorageDigest",
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:09/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:11",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s-b.mp4"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:12",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "PlayerUI-resumeDecision-panel"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 90,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:01/viewingStorageDigest",
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:09/viewingStorageDigest",
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:11/viewingStorageDigest"
        ],
        "relatedResults": [
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:01/viewingStorageObservation",
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:09/viewingStorageObservation",
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:11/viewingStorageObservation",
          "result://call:viewing-state-and-storage:completed-media-starts-from-beginning:13/matchedElement"
        ]
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:15",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:completed-media-starts-from-beginning:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "interaction-trace@1",
      "evidenceType": "interaction.trace",
      "id": "obligation:viewing-state-and-storage:completed-media-starts-from-beginning:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:viewing-state-and-storage:completed-media-starts-from-beginning:15",
      "rubric": "rubric:viewing-state-and-storage.completed-media-starts-from-beginning.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:viewing-state-and-storage:completed-media-starts-from-beginning:o02:default",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:viewing-state-and-storage:completed-media-starts-from-beginning:16",
      "rubric": "rubric:viewing-state-and-storage.completed-media-starts-from-beginning.o02@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:viewing-state-and-storage:completed-media-starts-from-beginning:o01:default"
      },
      {
        "observation": "obligation:viewing-state-and-storage:completed-media-starts-from-beginning:o02:default"
      }
    ]
  }
}
---
# 看完标记与之后从头播放

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
