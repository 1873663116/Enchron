---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:local-media-lifecycle",
  "title": "本地媒体导入、播放、轨道与留影",
  "scenarioRefs": [
    "scenario:local-media-lifecycle:injected-import-rejoins-ingest",
    "scenario:local-media-lifecycle:clean-flat-playback-main-gate",
    "scenario:local-media-lifecycle:clean-start-position-zero",
    "scenario:local-media-lifecycle:audio-track-switch-same-session",
    "scenario:local-media-lifecycle:subtitle-switch-and-off",
    "scenario:local-media-lifecycle:external-subtitle-source-matrix",
    "scenario:local-media-lifecycle:artwork-captured-on-exit",
    "scenario:local-media-lifecycle:automatic-play-next-resume-policy"
  ],
  "ordering": [
    {
      "after": "scenario:local-media-lifecycle:artwork-captured-on-exit",
      "before": "scenario:local-media-lifecycle:injected-import-rejoins-ingest"
    },
    {
      "after": "scenario:local-media-lifecycle:audio-track-switch-same-session",
      "before": "scenario:local-media-lifecycle:injected-import-rejoins-ingest"
    },
    {
      "after": "scenario:local-media-lifecycle:external-subtitle-source-matrix",
      "before": "scenario:local-media-lifecycle:injected-import-rejoins-ingest"
    },
    {
      "after": "scenario:local-media-lifecycle:subtitle-switch-and-off",
      "before": "scenario:local-media-lifecycle:injected-import-rejoins-ingest"
    }
  ],
  "sharedState": [
    {
      "key": "local-aggregate-staged",
      "schema": "fixture-set.local-aggregate-staged@2"
    }
  ]
}
---
# 本地媒体导入、播放、轨道与留影

The Journey groups scenarios and declares only the five reviewed state-handoff edges.
