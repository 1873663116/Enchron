---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:local-media-lifecycle:automatic-play-next-resume-policy",
  "title": "Automatic Play Next resume policy",
  "journey": "journey:local-media-lifecycle",
  "promiseRefs": [
    "promise:playback-queue:c01"
  ],
  "applicability": {
    "constant": true
  },
  "lane": "device",
  "estimatedCostMillis": 435000,
  "staticCases": [
    "default"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "settings"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Settings-category-playback"
        ]
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:03",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Settings-menu-resume-strategy",
          "Settings-menuOption-resume-strategy-askEveryTime"
        ]
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:04",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Settings-menu-end-behavior",
          "Settings-menuOption-end-behavior-playNext"
        ]
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "Settings-menu-controls-auto-hide",
          "Settings-menuOption-controls-auto-hide-never"
        ]
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:06",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:07",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:08",
      "maxInvocations": 1,
      "operation": "operation:media.import-staged@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:09",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:10",
      "maxInvocations": 1,
      "operation": "operation:media.open@2"
    },
    {
      "arguments": {
        "controls": "shown",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:11",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedMediaName": "sdr-bframe-multiaudio-avsync-120s.mp4",
        "minimumPositionMillis": 16000,
        "minimumRemainingMillis": 30000
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:12",
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
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:13",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:14",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "context": "main-window-browser",
        "identifiers": [
          "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-120s.mp4"
        ]
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:15",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-resumeDecision-panel"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:16",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-resumeDecision-primary"
        ]
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:17",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "controls": "shown",
        "deadlineSeconds": 45,
        "lifecycle": "playing",
        "presentation": "window"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:18",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedMediaName": "sdr-bframe-multiaudio-avsync-120s.mp4",
        "minimumPositionMillis": 12000,
        "minimumRemainingMillis": 30000
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:19",
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
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:20",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:21",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4"
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:22",
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
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:23",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:24",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 90,
        "differentSessionFrom": "result://call:local-media-lifecycle:automatic-play-next-resume-policy:24/session",
        "expectedMediaName": "sdr-bframe-multiaudio-avsync-120s.mp4",
        "minimumPositionMillis": 12000,
        "minimumRemainingMillis": 30000
      },
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:25",
      "maxInvocations": 1,
      "operation": "operation:playback.wait-position@2"
    },
    {
      "arguments": {},
      "callId": "call:local-media-lifecycle:automatic-play-next-resume-policy:26",
      "maxInvocations": 1,
      "operation": "operation:diagnostics.playback-state@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "default",
      "evidenceSchema": "playback-probe@1",
      "evidenceType": "playback.probe",
      "id": "obligation:local-media-lifecycle:automatic-play-next-resume-policy:o01:default",
      "oracle": "oracle:agent-structured-playback-probe@1",
      "producedByCall": "call:local-media-lifecycle:automatic-play-next-resume-policy:26",
      "rubric": "rubric:local-media-lifecycle.automatic-play-next-resume-policy.o01@1"
    }
  ],
  "success": {
    "observation": "obligation:local-media-lifecycle:automatic-play-next-resume-policy:o01:default"
  }
}
---
# Automatic Play Next resume policy

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
