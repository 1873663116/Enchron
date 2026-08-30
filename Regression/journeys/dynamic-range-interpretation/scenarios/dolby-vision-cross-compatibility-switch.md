---
{
  "schema": "enchron.regression.scenario",
  "schemaVersion": 1,
  "id": "scenario:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch",
  "title": "兼容 Dolby Vision 在 HDR10 或 HLG 解释间切换",
  "journey": "journey:dynamic-range-interpretation",
  "promiseRefs": [
    "promise:picture-interpretation:c03"
  ],
  "applicability": {
    "factEquals": {
      "fact": "fact:runtime.catalog-scope-included",
      "value": true
    }
  },
  "lane": "device",
  "estimatedCostMillis": 306000,
  "staticCases": [
    "profile-8-hdr10",
    "profile-8-hlg",
    "profile-5-no-fallback"
  ],
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [
    {
      "key": "dynamic-range-corpus-ready",
      "schema": "fixture-set.dynamic-range@2"
    }
  ],
  "operations": [
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:01",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:02",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:03",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:04",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-HDRFallback",
          "PlayerUI-VideoFormat-apply"
        ]
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:05",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "includeHDRFallback": true,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:06",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:07",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:08",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:09",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:10",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat",
          "PlayerUI-VideoFormat-HDRFallback",
          "PlayerUI-VideoFormat-apply"
        ]
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:11",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "includeHDRFallback": true,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:12",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    },
    {
      "arguments": {},
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:13",
      "maxInvocations": 1,
      "operation": "operation:app.relaunch@1"
    },
    {
      "arguments": {
        "tab": "files"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:14",
      "maxInvocations": 1,
      "operation": "operation:navigation.select-tab@1"
    },
    {
      "arguments": {
        "deadlineSeconds": 45,
        "expectedLanding": "window",
        "identifier": "MediaLibrary-grid-video-Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:15",
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
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:16",
      "maxInvocations": 1,
      "operation": "operation:playback.await-window-state@1"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-window-playback-surface",
          "PlayerUI-TopAction-videoFormat"
        ]
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:17",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifier": "PlayerUI-VideoFormat-HDRFallback",
        "requireMatchedElement": false
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:18",
      "maxInvocations": 1,
      "operation": "operation:accessibility.inspect@2"
    },
    {
      "arguments": {
        "context": "window",
        "identifiers": [
          "PlayerUI-VideoFormat-cancel"
        ]
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:19",
      "maxInvocations": 1,
      "operation": "operation:accessibility.activate@2"
    },
    {
      "arguments": {
        "context": "window",
        "count": 3,
        "includeHDRFallback": true,
        "minimumIntervalMillis": 1000
      },
      "callId": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:20",
      "maxInvocations": 1,
      "operation": "operation:evidence.capture-frames@1"
    }
  ],
  "obligations": [
    {
      "artifactClass": "coverage",
      "caseKey": "profile-8-hdr10",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:o01:profile-8-hdr10",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:06",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "profile-8-hlg",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:o01:profile-8-hlg",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:12",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1"
    },
    {
      "artifactClass": "coverage",
      "caseKey": "profile-5-no-fallback",
      "evidenceSchema": "window-control-plane@1",
      "evidenceType": "window.control-plane",
      "id": "obligation:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:o01:profile-5-no-fallback",
      "oracle": "oracle:agent-structured-window-control-plane@1",
      "producedByCall": "call:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:20",
      "rubric": "rubric:dynamic-range-interpretation.dolby-vision-cross-compatibility-switch.o01@1"
    }
  ],
  "success": {
    "all": [
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:o01:profile-8-hdr10"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:o01:profile-8-hlg"
      },
      {
        "observation": "obligation:dynamic-range-interpretation:dolby-vision-cross-compatibility-switch:o01:profile-5-no-fallback"
      }
    ]
  }
}
---
# 兼容 Dolby Vision 在 HDR10 或 HLG 解释间切换

Each ordered static case is an independent attempt. Evidence from another case, Scenario, lane, or attempt is inadmissible. Readiness records whether the approved Operation registry can execute the complete claim; prerequisite Preparation readiness is reported separately.
