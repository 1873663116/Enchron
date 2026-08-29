---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:emby-server-lifecycle.series-season-episode-navigation.o01@1",
  "title": "Series Season Episode Navigation",
  "criteria": [
    "The selected series detail exposes the server-declared seasons and the active season's episode identities.",
    "Changing season replaces the episode list without inventing a series-level play action."
  ],
  "negativeControls": [
    "An action return value without the post-action application state cannot satisfy the rubric.",
    "A missing required field, changed session identity where preservation is required, or stale snapshot produces a non-passing result.",
    "A poster-only cached view, stale episodes after season change, or navigation through the Emby tab icon mistaken for playback violates the rubric."
  ]
}
---
# Series Season Episode Navigation

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
