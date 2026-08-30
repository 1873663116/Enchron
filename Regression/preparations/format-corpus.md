---
{
  "schema": "enchron.regression.preparation",
  "schemaVersion": 1,
  "id": "preparation:format-corpus",
  "title": "Prepare format corpus",
  "lane": "device",
  "estimatedCostMillis": 60000,
  "readiness": "ready",
  "blockers": [],
  "prerequisites": [],
  "operations": [
    {
      "callId": "call:preparation:format-corpus:01",
      "operation": "operation:harness.ensure-session@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:02",
      "operation": "operation:app.relaunch@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:03",
      "operation": "operation:harness.reset-product-state@2",
      "arguments": {
        "rootFolderName": "Journey Fixture"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:04",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:05",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-multiaudio-subtitles-30s-v3",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:06",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-multiaudio-subtitles-30s.mkv"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:07",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-video-only-15s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:08",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-video-only-15s.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:09",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-audio-codec-matrix-15s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:10",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-audio-codec-matrix-15s.mkv"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:11",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-sdr-avc-bframe-duplicate-label-audio-30s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:12",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "sdr-bframe-duplicate-label-audio-30s.mkv"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:13",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-av1-flac-avsync-10s-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:14",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "av1-flac-avsync-10s.mkv"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:15",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-external-subrip-zh-cn-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:16",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "generated-external-ass-styled-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:17",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-mpeg4-part2-packed-bframes-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:18",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "packed_bframes.avi"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:19",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-dts-es-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:20",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "dts_es.dts"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:21",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-truehd-atmos-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:22",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "atmos.thd"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:23",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-fate-vorbis-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:24",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "1.0-test_small.ogg"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:25",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-mvhevc-short-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:26",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "spatial_lighthouse_flowers_waves_short.mov"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:27",
      "operation": "operation:media.stage-fixture@2",
      "arguments": {
        "fixtureID": "internal-apple-apmp-180-v1",
        "sourceRoot": "/Volumes/Cortisol/DevSpace/EnchronWorkspace/TestMedia"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:28",
      "operation": "operation:media.import-staged@2",
      "arguments": {
        "fileName": "APMP-180-example.mp4"
      },
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:29",
      "operation": "operation:library.snapshot@1",
      "arguments": {},
      "maxInvocations": 1
    },
    {
      "callId": "call:preparation:format-corpus:30",
      "operation": "operation:harness.assert-channels@2",
      "arguments": {},
      "maxInvocations": 1
    }
  ],
  "produces": [
    {
      "key": "format-corpus-ready",
      "schema": "fixture-set.format-corpus@2",
      "producedByCall": "call:preparation:format-corpus:30",
      "dependsOnTags": [
        "app.session",
        "audio.capture",
        "fixture.corpus",
        "lane.instance",
        "library.contents"
      ]
    }
  ]
}
---
# Prepare format corpus

The runtime Preparation adapter supplies this Preparation plan, implementation identity, readiness, blockers, and produced state.
