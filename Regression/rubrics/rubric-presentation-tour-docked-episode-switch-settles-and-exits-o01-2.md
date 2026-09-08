---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.docked-episode-switch-settles-and-exits.o01@2",
  "title": "Docked Episode Switch Lands In Portal",
  "criteria": [
    "The window-control-plane snapshot produced by playback.await-window-state@1 (presentation=portal, lifecycle=playing, controls=either, deadlineSeconds=45) at call 08, right after selecting 180_3D.mp4 from PlayerPanel-menu-more → PlayerPanel-menu-episodes in context docked, reports presentation=portal and attached=portal: the selected episode lands in the main-window cell of its own content family (docs/PLAYBACK_PRESENTATION_CONSTRAINTS.md, 换片时由内容族决定去向).",
    "fields.error equals none (MainView.swift:985, `error=\\(playbackRuntime.userVisibleIssue?.category.rawValue ?? \"none\")`) and lifecycle is playing, so the family change completed without a surfaced playback issue."
  ],
  "negativeControls": [
    "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
    "presentation or attached other than portal, a non-playing lifecycle, or a non-none fields.error fails the bound case; the 2026-09-08 escape stayed attached to the previous presentation with audio running."
  ]
}
---
# Docked Episode Switch Lands In Portal

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
