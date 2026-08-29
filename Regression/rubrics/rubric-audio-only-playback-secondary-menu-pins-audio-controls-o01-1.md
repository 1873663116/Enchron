---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1",
  "title": "Secondary Menu Pins Audio Controls",
  "criteria": [
    "For inside.m4a, one surface→More→Audio transaction and one surface→More→Playback Speed transaction each expose a real enabled secondary menu and keep playback controls visible through the 9000 ms probe, exceeding the product's exact 8000 ms idle auto-hide policy.",
    "The bound traces keep lifecycle Playing and show no subtitle, video-format, Dock, or Panorama actions in the audio-only control set."
  ],
  "negativeControls": [
    "Using the disabled subtitle menu as a case, omitting More, splitting one nested-menu route across controllers, controls hidden before 9000 ms, or any video-only action present fails the rubric."
  ]
}
---
# Secondary Menu Pins Audio Controls

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
