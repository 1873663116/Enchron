---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.episode-resume-and-start-actions.o01@1",
  "title": "Episode Resume And Start Actions",
  "criteria": [
    "When server progress exists, the episode detail exposes both Resume and Play from Beginning as independently delivered actions.",
    "Under the observed-position bound decided by HC-021, Resume opens within 5 seconds of server progress and Play from Beginning opens from 0 through 5 seconds inclusive, with the same Emby item identity.",
    "In the locked cold-open environment, click-to-first-changing-frame is at most 45000 ms; 90000 ms is only the harness liveness deadline."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "One action aliasing the other, using local progress, or changing the item identity violates the rubric.",
    "Treating the 90000 ms liveness deadline as the product threshold violates HC-018."
  ]
}
---
# Episode Resume And Start Actions

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
