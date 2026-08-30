---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:format-editor-hosts-window-and-portal",
  "title": "Window 与 Portal 共用窗口格式编辑入口",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:format-editing:c01"
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
    "window",
    "portal"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:03",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-cancel"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-VideoFormat",
        "relatedResults": [
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:05/response",
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:05/tappedIdentifiers",
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:06/response",
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:06/tappedIdentifiers"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:08",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:09",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:10",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "either",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:11",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:12",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "context": "portal",
        "labels": [
          "Playback surface"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "portal",
        "identifiers": [
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-cancel"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:14",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "portal",
        "labels": [
          "Playback surface"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:15",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "portal",
        "identifiers": [
          "PlayerUI-TopAction-videoFormat"
        ],
        "relatedResults": [
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:13/response",
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:14/response",
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:14/tappedIdentifiers",
          "result://call:presentation-tour:format-editor-hosts-window-and-portal:15/response"
        ]
      },
      "callId": "call:presentation-tour:format-editor-hosts-window-and-portal:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "window",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:presentation-tour:format-editor-hosts-window-and-portal:o01:window",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:presentation-tour:format-editor-hosts-window-and-portal:07",
      "rubric": "rubric:presentation-tour.format-editor-hosts-window-and-portal.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "portal",
      "evidenceSchema": "accessibility-tree@1",
      "evidenceType": "accessibility.tree",
      "id": "obligation:presentation-tour:format-editor-hosts-window-and-portal:o01:portal",
      "oracle": "oracle:agent-structured-accessibility-tree@1",
      "producedByCall": "call:presentation-tour:format-editor-hosts-window-and-portal:16",
      "rubric": "rubric:presentation-tour.format-editor-hosts-window-and-portal.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:format-editor-hosts-window-and-portal:o01:window"
      },
      {
        "observation": "obligation:presentation-tour:format-editor-hosts-window-and-portal:o01:portal"
      }
    ]
  }
}
---
# Window 与 Portal 共用窗口格式编辑入口

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
