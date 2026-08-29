---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:presentation-tour.spatial-controls-summon.o01@1",
  "title": "Spatial Controls Summon",
  "criteria": [
    "After one successful Device Hub preparation, each case starts from a fresh Docked or Panorama baseline; show sends exactly one accepted spatialTap and ends controlsVisible=true, while hide sends exactly two ordered accepted spatialTap events and ends controlsVisible=false.",
    "Every accepted event names the active presentation's real input entity, precedes a toggle source=spatialTap, and for show completes placement before entity enablement; no Window Scene input event occurs."
  ],
  "negativeControls": [
    "allowSmall, an unprepared/small Device Hub window, a diagnostic probe entity, a missing/extra spatialTap, toggle without the input event, wrong final parity, or controls enabled before placement fails the rubric."
  ]
}
---
# Spatial Controls Summon

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
