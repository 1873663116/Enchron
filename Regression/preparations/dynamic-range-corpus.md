---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:dynamic-range-corpus",
  "title": "Prepare dynamic range corpus",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:dynamic-range-corpus:01",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:02",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:03",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:04",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:05",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-hlg-hevc10-avsync-10s-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:06",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "hlg-hevc-10bit-avsync-10s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:07",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-pq-hevc10-avsync-10s-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:08",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "pq-hevc-10bit-avsync-10s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:09",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p5-hd-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:10",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "Patterns_Of_Nature_DoVi_24_P5_HD_HEVC-2mbps_DD+JOC-768kbps_iOS.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:11",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p7-fel-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:12",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "FEL_test_for_AVS.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:13",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p81-hdr10-hd-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:14",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "Patterns_Of_Nature_HDR10-P8.1_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:15",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p84-hlg-hd-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:16",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "Patterns_Of_Nature_HLG-P8.4_HD_24_H265-2Mbps_DD+JOC-768Kbps.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:17",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p100-av1-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:18",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "media-video-dav1-dav1-1.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:19",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p101-av1-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:20",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "media-video-av01-dav1-db1p-1.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:21",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-dolby-vision-p104-av1-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:22",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "media-video-av01-dav1-db4h-1.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:23",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-dolby-vision-p20-3d-v1",
        "sourceRoot": "workspace://TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:24",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "3D-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:25",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:dynamic-range-corpus:26",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "dynamic-range-corpus-ready",
      "schema": "fixture-set.dynamic-range@2",
      "producedByCall": "call:preparation:dynamic-range-corpus:26",
      "dependsOnTags": [
        "app.session",
        "display.capture",
        "fixture.corpus",
        "lane.instance",
        "library.contents"
      ]
    }
  ]
}
---
# Prepare dynamic range corpus

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
