---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:format-coverage.audio-retirement-on-failure.o01@1",
  "title": "Audio Retirement On Failure",
  "criteria": [
    "The structural-test artifact reports succeeded true with returnCode 0, and its check and command are the allowlisted pair registered for this case: audio-retirement-open runs swift test --package-path Packages/PlaybackCore --filter audioOpenFailureRetiresAudioButVideoStillDelivers; audio-retirement-prewarm runs --filter audioThatNeverPrerollsKeepsTheSessionLoadingWithoutRetiringAudio; audio-retirement-playback runs --filter audioReadFailureFailsTheWholeSession; audio-retirement-seek runs --filter audioSeekOpenFailureFailsTheWholeSession; and audio-retirement-renderer runs --filter audioRendererFailureFailsTheWholeSession. The artifact's check is audio-retirement- followed by the bound caseKey.",
    "assertionPayloads holds exactly one object, and it alone decides the behaviour. Its assertion is audio-failure-scope and its check equals the artifact's own check, so the payload belongs to this run. failureStage equals the phase registered for the case: audioProvider.openFailed.videoContinues for open, none for prewarm, audioProvider.readFailed for playback, audioProvider.seekOpenFailed for seek, and audioRenderer.failed for renderer. audioRetired is true for open and false for the other four. For open the session continues: sessionLifecycle is playing or paused and readinessState is playable. For prewarm the session stays in loading: sessionLifecycle is loading and readinessState is loading, which shows the track was kept while its data was missing. For playback, seek and renderer the session fails as a whole: sessionLifecycle is failed."
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
