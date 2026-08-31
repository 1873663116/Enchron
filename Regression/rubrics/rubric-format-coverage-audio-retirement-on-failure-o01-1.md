---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.audio-retirement-on-failure.o01@1",
  "title": "Audio Retirement On Failure",
  "criteria": [
    "The structural-test artifact reports succeeded true with returnCode 0, and its check and command are the allowlisted pair registered for this case: audio-retirement-open runs swift test --package-path Packages/PlaybackCore --filter audioOpenFailureRetiresAudioButVideoStillDelivers; audio-retirement-prewarm runs --filter audioPrerollFailureRetiresAudioButVideoStillDelivers; audio-retirement-playback runs --filter audioReadFailureRetiresAudioButVideoStillDelivers; audio-retirement-seek runs --filter audioSeekOpenFailureRetiresAudioButVideoStillDelivers; and audio-retirement-renderer runs --filter audioRendererFailureRetiresAudioAndVideoContinues. The artifact's check is audio-retirement- followed by the bound caseKey.",
    "assertionPayloads holds exactly one object, and it alone decides the behaviour. Its assertion is audio-retirement-nonfatal-seek and its check equals the artifact's own check, so the payload belongs to this run. Its expectedStage is the failure phase registered for the case -- audioProvider.openFailed.videoContinues for open, audioRenderer.prerollFailed.videoContinues for prewarm, audioProvider.readFailed.videoContinues for playback, audioProvider.seekOpenFailed.videoContinues for seek, audioRenderer.failed.videoContinues for renderer -- and failureStageAfterSeek equals it, so the audio that retired retired for that reason. Retirement is nonfatal: lifecycleBeforeSeek is playing or paused, lifecycleAfterSeek is paused, neither is failed, audioRetiredAfterSeek is true and lastErrorPresentAfterSeek is false. The seek stays in one media session and advances video: mediaSessionIDAfterSeek equals mediaSessionIDBeforeSeek and both are non-empty, and videoPresentationTimeSecondsAfterSeek is a number at least seekTargetSeconds, which is 30."
  ],
  "negativeControls": [
    "A passing test for another failure phase cannot satisfy this case.",
    "A compile-only result, a zero-test selection, or a structural artifact whose command differs from the allowlisted command cannot satisfy the rubric.",
    "A command exit code or test name without the structured assertion payload cannot satisfy the rubric, and neither can more or fewer than one payload. A lifecycleAfterSeek of failed, an audioRetiredAfterSeek of false, a videoPresentationTimeSecondsAfterSeek that is null or below seekTargetSeconds -- stalled post-seek video -- or a mediaSessionIDAfterSeek different from mediaSessionIDBeforeSeek -- a replacement media session -- violates the commitment."
  ]
}
---
# Audio Retirement On Failure

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
