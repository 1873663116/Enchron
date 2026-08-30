---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1",
  "title": "Secondary Menu Pins Audio Controls",
  "criteria": [
    "relatedResults[0] contains the More-menu transaction registered for the bound case: audio-menu={PlayerUI-window-playback-surface→PlayerUI-TopAction-more→PlayerUI-menu-audio}; speed-menu={PlayerUI-window-playback-surface→PlayerUI-TopAction-more→PlayerUI-menu-speed}. The transaction exposes a real enabled secondary menu and the bound probe keeps playback controls visible through the 9000 ms settle.",
    "The bound trace keeps lifecycle Playing and shows no subtitle, video-format, Dock, or Panorama actions in the audio-only control set."
  ],
  "negativeControls": [
    "A relatedResults[0] identifier path that differs from the bound case, omitted More step, PlayerPanel-menu-* on a window host, split nested-menu route, controls hidden before 9000 ms, or any video-only action fails the bound case."
  ]
}
---
# Secondary Menu Pins Audio Controls

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
