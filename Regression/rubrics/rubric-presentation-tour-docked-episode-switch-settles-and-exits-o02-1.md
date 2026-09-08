---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.docked-episode-switch-settles-and-exits.o02@1",
  "title": "Docked Episode Switch Exits Without A Playback Issue",
  "criteria": [
    "The window-control-plane snapshot produced by presentation.exit-spatial@1 (from=docked, deadlineSeconds=30) reports presentation=window, attached=window, and the same session identity the docked-resident probe observed, per MainView.swift:927 (`session=`) and MainView.swift:926 (`lifecycle=`).",
    "fields.error equals none (MainView.swift:985, `error=\\(playbackRuntime.userVisibleIssue?.category.rawValue ?? \"none\")`), so the exit that used to fail with rendererReleaseUnavailable now completes without a surfaced playback issue."
  ],
  "negativeControls": [
    "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
    "attached other than window, a changed session, or a non-none fields.error (including a rendererReleaseUnavailable-class failure) fails the bound case."
  ]
}
---
# Docked Episode Switch Exits Without A Playback Issue

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
