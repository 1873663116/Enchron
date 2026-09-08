---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.portal-episode-switch-lands-in-window.o01@1",
  "title": "Portal Episode Switch To A Flat Episode Lands In Window",
  "criteria": [
    "The window-control-plane snapshot produced by playback.await-window-state@1 (presentation=window, lifecycle=playing, controls=either, deadlineSeconds=45) at call 07, right after selecting sdr-bframe-multiaudio-avsync-120s.mp4 from PlayerUI-TopAction-more → PlayerUI-menu-episodes in context portal, reports presentation=window and attached=window: the selected episode lands in the main-window cell of its own content family (docs/PLAYBACK_PRESENTATION_CONSTRAINTS.md, 换片时由内容族决定去向).",
    "fields.error equals none (MainView.swift:985, `error=\\(playbackRuntime.userVisibleIssue?.category.rawValue ?? \"none\")`) and lifecycle is playing, so the family change completed without a surfaced playback issue."
  ],
  "negativeControls": [
    "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
    "presentation or attached other than window, a non-playing lifecycle, or a non-none fields.error fails the bound case; the 2026-09-08 escape stayed attached to the previous presentation with audio running."
  ]
}
---
# Portal Episode Switch To A Flat Episode Lands In Window

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
