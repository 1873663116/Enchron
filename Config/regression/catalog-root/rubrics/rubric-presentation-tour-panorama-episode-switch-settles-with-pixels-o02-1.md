---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.panorama-episode-switch-settles-with-pixels.o02@1",
  "title": "Panorama Episode Switch Exits Without A Playback Issue",
  "criteria": [
    "The window-control-plane snapshot produced by presentation.exit-spatial@1 (from=panorama, deadlineSeconds=30) reports presentation=portal and attached=portal, matching the reviewed panorama-to-portal exit route (promise:mode-transitions:c04) rather than window.",
    "fields.error equals none (MainView.swift:985) and the session identity is unchanged from the panorama-resident probe, so the switched episode continues without a surfaced playback issue after exit."
  ],
  "negativeControls": [
    "Controller success without the application-side window-control-plane delivery is not evidence of product behavior.",
    "attached other than portal, a changed session, or a non-none fields.error fails the bound case."
  ]
}
---
# Panorama Episode Switch Exits Without A Playback Issue

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
