---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:viewing-state-and-storage:storage-rows-report-and-clear",
  "title": "两条存储行分别报数并清除",
  "journey": "journey:viewing-state-and-storage",
  "promiseRefs": [
    "promise:cache-and-artwork:c05"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "either",
  "estimatedCostMillis": 660000,
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
        "target": "artwork-cache"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:01",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "target": "container-index-cache"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:02",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "awaitEmptyStores": [
          "artwork",
          "container-index"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:03",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:04",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "FileBrowsing-SourcesSidebar-source-media-library"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "viewing-storage-16m01s.mp4"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:06",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-viewing-storage-16m01s.mp4"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:07",
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
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:08",
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
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:09",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:10",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:13",
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
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "expectedMediaName": "sdr-bframe-aggregate-30s.mkv",
        "minimumPositionMillis": 3000,
        "minimumRemainingMillis": 3000
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:15",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-InfoBar-button-back"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:03/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:17",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "tab": "settings"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:18",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Settings-category-storagePrivacy"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:19",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Settings-StoragePrivacy-group",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:20",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "target": "artwork-cache"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:21",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "awaitEmptyStores": [
          "artwork"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:03/viewingStorageDigest",
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:17/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:22",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Settings-StoragePrivacy-group",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:23",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "target": "container-index-cache"
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:24",
      "maxInvocations": 1,
      "operation": "operation:storage.clear@1"
    },
    {
      "arguments": {
        "awaitEmptyStores": [
          "artwork",
          "container-index"
        ],
        "deadlineSeconds": 30,
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:03/viewingStorageDigest",
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:17/viewingStorageDigest",
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:22/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:25",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.surface-probe@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifier": "Settings-StoragePrivacy-group",
        "requireMatchedElement": true
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:26",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "includeViewingStorage": true,
        "priorViewingStorageDigests": [
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:03/viewingStorageDigest",
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:17/viewingStorageDigest",
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:22/viewingStorageDigest",
          "result://call:viewing-state-and-storage:storage-rows-report-and-clear:25/viewingStorageDigest"
        ]
      },
      "callId": "call:viewing-state-and-storage:storage-rows-report-and-clear:27",
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
      "id": "obligation:viewing-state-and-storage:storage-rows-report-and-clear:o01:default",
      "oracle": "oracle:agent-structured-interaction-trace@1",
      "producedByCall": "call:viewing-state-and-storage:storage-rows-report-and-clear:27",
      "rubric": "rubric:viewing-state-and-storage.storage-rows-report-and-clear.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:viewing-state-and-storage:storage-rows-report-and-clear:o01:default"
  }
}
---
# 两条存储行分别报数并清除

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
