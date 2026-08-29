---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:local-media-lifecycle.automatic-play-next-resume-policy.o01@1",
  "title": "Automatic Play Next resume policy",
  "criteria": [
    "The terminal playback probe has mediaName=sdr-bframe-multiaudio-avsync-120s.mp4, position at least 12 seconds, at least 30 seconds remaining, and a session different from the first-item baseline.",
    "The terminal playback probe has resumePromptPresentations=1, automaticResumeBypasses=1, and pendingResumePrompt=false: the one direct reopen presented Ask Every Time, while automatic Play Next resumed without a second prompt."
  ],
  "negativeControls": [
    "A missing direct-open prompt, any automatic-continuation prompt, a terminal position below the saved range, unchanged session identity, or the wrong mediaName violates HC-013."
  ]
}
---
# Automatic Play Next resume policy

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
