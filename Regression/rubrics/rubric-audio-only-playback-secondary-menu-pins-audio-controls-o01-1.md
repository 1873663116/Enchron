---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:audio-only-playback.secondary-menu-pins-audio-controls.o01@1",
  "title": "Secondary Menu Pins Audio Controls",
  "criteria": [
    "relatedResults[0] is the More-menu activation's tappedIdentifiers: exactly the ordered list registered for the bound case, audio-menu=[PlayerUI-window-playback-surface, PlayerUI-TopAction-more, PlayerUI-menu-audio] and speed-menu=[PlayerUI-window-playback-surface, PlayerUI-TopAction-more, PlayerUI-menu-speed]. relatedResults[1] is that same call's tapSequence response, succeeded, reporting one command that tapped three elements in sequence, so the nested route was delivered without a second controller round trip.",
    "The bound probe's own interactionTrace, measured from the pre-route cursor this Scenario passes as cursorToken, contains the product-side line reachability top actions delivered action=menu.more, so the More menu's own content appeared rather than the controller merely reporting a successful tap.",
    "The bound control-plane fields, read after the 9000 ms settle that outlasts the controls auto-hide window, still report controls=shown and lifecycle Playing, so the open secondary menu pinned the playback controls.",
    "The bound control set carries no subtitle, video-format, Dock, or Panorama action."
  ],
  "negativeControls": [
    "A relatedResults[0] identifier list that differs from the bound case, an omitted PlayerUI-TopAction-more step, a PlayerPanel-menu-* route on a window host, or a split nested-menu route — more than one activation bound to the case, or a response that does not report the whole route in one sequence — fails the bound case.",
    "A controller-only success with no reachability top actions delivered action=menu.more line in the bound interactionTrace, controls=hidden at the end of the 9000 ms settle, or any video-only action in the bound control set fails the bound case."
  ]
}
---
# Secondary Menu Pins Audio Controls

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
