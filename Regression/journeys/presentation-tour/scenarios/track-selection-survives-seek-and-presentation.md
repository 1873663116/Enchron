---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:presentation-tour:track-selection-survives-seek-and-presentation",
  "title": "轨道选择跨 seek 与呈现切换保持",
  "journey": "journey:presentation-tour",
  "promiseRefs": [
    "promise:track-selection:c06"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 540000,
  "staticCases": [
    "seek",
    "window-docked-window",
    "window-portal-window",
    "format-replacement"
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
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:04",
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
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:05",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-2"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles"
        ],
        "labels": [
          "sdr-bframe-aggregate-30s.zh-CN.srt"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:07",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "positionMillionths": 500000
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:08",
      "maxInvocations": 1,
      "operation": "operation:playback.seek@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:06/response",
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:07/response"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:09",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:10",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:11",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:12",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:13",
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
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:14",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-2"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:15",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles"
        ],
        "labels": [
          "sdr-bframe-aggregate-30s.zh-CN.srt"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:17",
      "maxInvocations": 1,
      "operation": "operation:presentation.enter-docked-skybox@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "from": "docked"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:18",
      "maxInvocations": 1,
      "operation": "operation:presentation.exit-spatial@1"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:15/response",
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:16/response"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:19",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:20",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:21",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:22",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:23",
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
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:24",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-2"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:25",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles"
        ],
        "labels": [
          "sdr-bframe-aggregate-30s.zh-CN.srt"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:26",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:27",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "flat",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:28",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:25/response",
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:26/response"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:29",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {},
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:30",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:31",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "labels": [
          "Enchron Regression WebDAV"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:32",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "FileBrowsing-grid-video-sdr-bframe-aggregate-30s.mkv"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:33",
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
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:34",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-audio",
          "PlayerUI-menu-audio-2"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:35",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-more",
          "PlayerUI-menu-subtitles"
        ],
        "labels": [
          "sdr-bframe-aggregate-30s.zh-CN.srt"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:36",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "deadlineSeconds": 30,
        "projection": "equirectangular180",
        "stereoLayout": "mono"
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:37",
      "maxInvocations": 1,
      "operation": "operation:format.apply@2"
    },
    {
      "arguments": {
        "relatedResults": [
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:35/response",
          "result://call:presentation-tour:track-selection-survives-seek-and-presentation:36/response"
        ]
      },
      "callId": "call:presentation-tour:track-selection-survives-seek-and-presentation:38",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "seek",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:seek",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:presentation-tour:track-selection-survives-seek-and-presentation:09",
      "rubric": "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "window-docked-window",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:window-docked-window",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:presentation-tour:track-selection-survives-seek-and-presentation:19",
      "rubric": "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "window-portal-window",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:window-portal-window",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:presentation-tour:track-selection-survives-seek-and-presentation:29",
      "rubric": "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "format-replacement",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:format-replacement",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:presentation-tour:track-selection-survives-seek-and-presentation:38",
      "rubric": "rubric:presentation-tour.track-selection-survives-seek-and-presentation.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:seek"
      },
      {
        "observation": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:window-docked-window"
      },
      {
        "observation": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:window-portal-window"
      },
      {
        "observation": "obligation:presentation-tour:track-selection-survives-seek-and-presentation:o01:format-replacement"
      }
    ]
  }
}
---
# 轨道选择跨 seek 与呈现切换保持

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
