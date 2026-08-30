---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1",
  "title": "Secondary Menu Pins Audio Controls",
  "criteria": [
    "For caseKey audio-menu, the bound trace contains one surface to More to Audio transaction that exposes a real enabled secondary menu and keeps playback controls visible through the 9000 ms probe.",
    "For caseKey speed-menu, the bound trace contains one surface to More to Playback Speed transaction that exposes a real enabled secondary menu and keeps playback controls visible through the 9000 ms probe.",
    "The bound trace keeps lifecycle Playing and shows no subtitle, video-format, Dock, or Panorama actions in the audio-only control set."
  ],
  "negativeControls": [
    "A trace for the other case, omitted More step, split nested-menu route, controls hidden before 9000 ms, or any video-only action fails the bound case."
  ]
}
---
# Secondary Menu Pins Audio Controls

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
