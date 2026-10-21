---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.automatic-play-next-resume-policy.o01@1",
  "title": "Ended Play Next resume policy",
  "criteria": [
    "The terminal playback probe has mediaName=viewing-storage-16m01s.mp4, position at least 20 seconds, at least 300 seconds remaining, and session different from relatedResults[0], which is the first-item diagnostics.playback-state@1 session captured before the ended Play Next tap. That fixture runs 961.0 s -- generated-viewing-storage-h264-16m01s-v1 in Tests/Fixtures/fixture-registry.json -- so it is above ViewingStatePolicy.minimumContentDurationSeconds of 900 and its exit actually retains a resumable status for the reopen and the ended continuation to find; the 30-second item that ends naturally is below that constant and correctly retains nothing.",
    "The terminal playback probe has resumePromptPresentations=1, automaticResumeBypasses=1, and pendingResumePrompt=false: the one direct reopen presented Ask Every Time, while the ended Play Next continuation resumed without a second prompt. Both counters increment only on the seconds > 0 arms of requestPlayback, which the 961-second fixture's saved position supplies."
  ],
  "negativeControls": [
    "A missing direct-open prompt, a resume prompt on the ended Play Next path, a terminal position below the saved range, session equal to relatedResults[0], or a mediaName other than viewing-storage-16m01s.mp4 violates HC-013. The next item playing without the intervening await-window-state@1 ended observation and the PlayerPanel-button-play activation means the product still advances by itself and fails the claim."
  ]
}
---
# Ended Play Next resume policy

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
