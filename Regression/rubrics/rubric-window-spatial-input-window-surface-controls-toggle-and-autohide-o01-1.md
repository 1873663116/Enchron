---
{
  "schema": "enchron.regression.rubric",
  "schemaVersion": 1,
  "id": "rubric:window-spatial-input.window-surface-controls-toggle-and-autohide.o01@1",
  "title": "Window Surface Controls Toggle And Autohide",
  "criteria": [
    "Three Device Hub gaze-and-pinch actions after the baseline produce exactly three accepted EnchronWindowInput.surface spatialTap events, and the bound interactionTrace carries exactly three controlsVisibility event=surface-toggle records reading state=shown, then state=hidden, then state=shown, each stamped autoHideSeconds=25. Every controlsVisibility record in the trace that carries a lifecycle reads lifecycle=playing and the bound control-plane fields read lifecycle Playing. No controlsVisibility event=auto-hide record falls between the first and the third toggle, and their interactionMillis span is under 25000 ms, so all three pinches landed inside one idle window and the middle reading is a delivered toggle rather than the idle timer. That span is this Scenario's bound on inter-call latency: at or above one idle window the run was too slow to have tested the toggle at all, and the criterion is not Satisfied.",
    "The final probe waits 30000 ms after the third action. The bound interactionTrace then ends with exactly one controlsVisibility event=auto-hide state=hidden record carrying delaySeconds=25 and lifecycle=playing, whose scheduledAtMillis equals that of the controlsVisibility event=timer-scheduled record emitted after the third toggle and whose hiddenAtMillis is at least 25000 ms later, and the bound window control-plane fields read chrome=off with lifecycle Playing. The idle timer therefore ran its full window from the third delivered interaction rather than from the first, which is the 25 s window preparation:window-input-fixture call 01 pins through TEST_RUNNER_ENCHRON_CONTROLS_AUTO_HIDE_SECONDS and the record itself reports."
  ],
  "negativeControls": [
    "A duplicate import, toggleControls command, XCUITest-only tap return, missing or extra spatialTap, wrong visibility parity, an auto-hide record interleaved between the three toggles, a toggle span of 25000 ms or more, an auto-hide record whose scheduledAtMillis predates the third toggle, non-Playing lifecycle, or controls still visible after 30000 ms fails the rubric."
  ]
}
---
# Window Surface Controls Toggle And Autohide

The Oracle evaluates only the bound case artifact and returns a structured result for every criterion and negative control.
