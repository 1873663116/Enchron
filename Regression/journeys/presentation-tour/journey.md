---
{
  "schema": "enchron.regression.journey",
  "schemaVersion": 1,
  "id": "journey:presentation-tour",
  "title": "呈现态、格式编辑与空间控件环游",
  "scenarioRefs": [
    "scenario:presentation-tour:track-selection-survives-seek-and-presentation",
    "scenario:presentation-tour:initial-presentation-routing",
    "scenario:presentation-tour:window-to-portal-format-route",
    "scenario:presentation-tour:portal-to-panorama-explicit-entry",
    "scenario:presentation-tour:panorama-to-portal-exit",
    "scenario:presentation-tour:window-docked-round-trip",
    "scenario:presentation-tour:transition-timeout-rolls-back",
    "scenario:presentation-tour:format-editor-hosts-window-and-portal",
    "scenario:presentation-tour:portal-format-and-panorama-actions-coexist",
    "scenario:presentation-tour:automatic-source-provenance",
    "scenario:presentation-tour:format-application-route",
    "scenario:presentation-tour:spatial-controls-summon",
    "scenario:presentation-tour:docked-episode-switch-settles-and-exits",
    "scenario:presentation-tour:panorama-episode-switch-settles-with-pixels"
  ],
  "ordering": [],
  "sharedState": [
    {
      "key": "presentation-fixtures-ready",
      "schema": "fixture-set.presentation-tour@2"
    }
  ]
}
---
# 呈现态、格式编辑与空间控件环游

The Journey groups scenarios and declares only the reviewed state-handoff edges.
